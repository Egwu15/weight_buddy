package httpapi

import (
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/tedif/weight-buddy-backend/internal/ai"
	"github.com/tedif/weight-buddy-backend/internal/limits"
)

// maxAudioUpload caps an uploaded recording. Voice notes are small; this is a
// safety net against a runaway client.
const maxAudioUpload = 25 << 20 // 25 MiB

type parseRequest struct {
	Transcript string   `json:"transcript"`
	WeightKg   *float64 `json:"weight_kg"`
}

type chatRequest struct {
	SystemPrompt string       `json:"system_prompt"`
	Messages     []ai.Message `json:"messages"`
}

type exchangeRequest struct {
	Exchange []ai.Message `json:"exchange"`
}

// handleTranscribe proxies an audio upload to the provider and returns the
// transcript.
func (d Deps) handleTranscribe(w http.ResponseWriter, r *http.Request) {
	user, cost, ok := d.gate(w, r, limits.KindTranscribe)
	if !ok {
		return
	}

	if err := r.ParseMultipartForm(maxAudioUpload); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Expected a multipart upload with an audio file.")
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Expected a multipart upload with an audio file.")
		return
	}
	defer func() { _ = file.Close() }()

	audio, err := io.ReadAll(io.LimitReader(file, maxAudioUpload))
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Could not read the audio upload.")
		return
	}

	text, err := d.Provider.Transcribe(r.Context(), ai.TranscribeRequest{
		Audio:    audio,
		Filename: header.Filename,
		Prompt:   strings.TrimSpace(r.FormValue("prompt")),
	})
	if err != nil {
		d.aiError(w, r, err)
		return
	}
	if strings.TrimSpace(text) == "" {
		writeError(w, http.StatusUnprocessableEntity, "empty_transcript",
			"Could not hear anything in that recording. Try again a little closer.")
		return
	}

	d.recordUsage(r.Context(), user, limits.KindTranscribe, cost)
	writeJSON(w, http.StatusOK, map[string]string{"text": text})
}

func (d Deps) handleParseMeal(w http.ResponseWriter, r *http.Request) {
	d.handleParse(w, r, limits.KindParseMeal, "meal")
}

func (d Deps) handleParseExercise(w http.ResponseWriter, r *http.Request) {
	d.handleParse(w, r, limits.KindParseExercise, "exercise")
}

// handleParseAuto lets the model decide whether a transcript describes a meal
// or a workout. The app's voice flow uses this; the biased endpoints above are
// for callers that already know.
func (d Deps) handleParseAuto(w http.ResponseWriter, r *http.Request) {
	d.handleParse(w, r, limits.KindParse, "")
}

// handleParse turns a transcript into a structured meal or exercise log. Both
// endpoints share one strict schema; entryType biases which shape the model
// fills in (empty means it decides).
func (d Deps) handleParse(w http.ResponseWriter, r *http.Request, kind limits.Kind, entryType string) {
	user, cost, ok := d.gate(w, r, kind)
	if !ok {
		return
	}

	var req parseRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Expected a JSON body with a transcript.")
		return
	}
	if strings.TrimSpace(req.Transcript) == "" {
		writeError(w, http.StatusBadRequest, "invalid_request", "The transcript must not be empty.")
		return
	}

	system := ai.ParseSystemPrompt(time.Now())
	if entryType != "" {
		system += "\nSet entry_type to \"" + entryType + "\"."
	}

	raw, err := d.Provider.Structured(r.Context(), ai.StructuredRequest{
		SystemPrompt: system,
		UserContent:  req.Transcript,
		SchemaName:   "food_exercise_log",
		Schema:       ai.ParseSchema,
	})
	if err != nil {
		d.aiError(w, r, err)
		return
	}

	d.recordUsage(r.Context(), user, kind, cost)
	writeJSONRaw(w, http.StatusOK, raw)
}

// handleChat proxies one coaching exchange.
func (d Deps) handleChat(w http.ResponseWriter, r *http.Request) {
	user, cost, ok := d.gate(w, r, limits.KindChat)
	if !ok {
		return
	}

	var req chatRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Expected a JSON body with a system_prompt and messages.")
		return
	}
	if strings.TrimSpace(req.SystemPrompt) == "" || len(req.Messages) == 0 {
		writeError(w, http.StatusBadRequest, "invalid_request", "system_prompt and messages are required.")
		return
	}

	reply, err := d.Provider.Chat(r.Context(), ai.ChatRequest{
		SystemPrompt: req.SystemPrompt,
		Messages:     req.Messages,
	})
	if err != nil {
		d.aiError(w, r, err)
		return
	}

	d.recordUsage(r.Context(), user, limits.KindChat, cost)
	writeJSON(w, http.StatusOK, map[string]string{"reply": strings.TrimSpace(reply)})
}

// handleDistillMemories reviews an exchange and returns durable facts.
func (d Deps) handleDistillMemories(w http.ResponseWriter, r *http.Request) {
	user, cost, ok := d.gate(w, r, limits.KindDistillMemories)
	if !ok {
		return
	}

	var req exchangeRequest
	if err := decodeJSON(w, r, &req); err != nil || len(req.Exchange) == 0 {
		writeError(w, http.StatusBadRequest, "invalid_request", "Expected a JSON body with an exchange.")
		return
	}

	raw, err := d.Provider.Structured(r.Context(), ai.StructuredRequest{
		SystemPrompt: ai.MemorySystemPrompt,
		UserContent:  flattenExchange(req.Exchange),
		SchemaName:   "memory_distill",
		Schema:       ai.MemorySchema,
	})
	if err != nil {
		d.aiError(w, r, err)
		return
	}

	d.recordUsage(r.Context(), user, limits.KindDistillMemories, cost)
	writeJSONRaw(w, http.StatusOK, raw)
}

// handleExtractExercises scans an exchange for actionable exercises.
func (d Deps) handleExtractExercises(w http.ResponseWriter, r *http.Request) {
	user, cost, ok := d.gate(w, r, limits.KindExtractExercises)
	if !ok {
		return
	}

	var req exchangeRequest
	if err := decodeJSON(w, r, &req); err != nil || len(req.Exchange) == 0 {
		writeError(w, http.StatusBadRequest, "invalid_request", "Expected a JSON body with an exchange.")
		return
	}

	raw, err := d.Provider.Structured(r.Context(), ai.StructuredRequest{
		SystemPrompt: ai.ExerciseSystemPrompt,
		UserContent:  flattenExchange(req.Exchange),
		SchemaName:   "exercise_extraction",
		Schema:       ai.ExerciseSchema,
	})
	if err != nil {
		d.aiError(w, r, err)
		return
	}

	d.recordUsage(r.Context(), user, limits.KindExtractExercises, cost)
	writeJSONRaw(w, http.StatusOK, raw)
}

// flattenExchange renders a conversation the way the prompts expect.
func flattenExchange(messages []ai.Message) string {
	var b strings.Builder
	for i, m := range messages {
		if i > 0 {
			b.WriteString("\n\n")
		}
		b.WriteString(strings.ToUpper(m.Role))
		b.WriteString(": ")
		b.WriteString(m.Content)
	}
	return b.String()
}

// aiError maps a provider failure to a client-safe response. The underlying
// error is logged; the client only sees a friendly message.
func (d Deps) aiError(w http.ResponseWriter, r *http.Request, err error) {
	if errors.Is(err, ai.ErrNotConfigured) {
		writeError(w, http.StatusServiceUnavailable, "not_configured", "The assistant is not available right now.")
		return
	}
	if d.Logger != nil {
		d.Logger.ErrorContext(r.Context(), "ai provider call failed", "path", r.URL.Path, "err", err)
	}
	writeError(w, http.StatusBadGateway, "ai_unavailable",
		"The assistant is unavailable right now. Try again in a moment.")
}
