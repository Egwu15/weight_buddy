package ai

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"time"
)

// maxProviderResponse caps how much of an AI response we read into memory.
const maxProviderResponse = 4 << 20 // 4 MiB

// OpenAIConfig configures the OpenAI-backed provider.
type OpenAIConfig struct {
	APIKey          string
	BaseURL         string
	ParseModel      string
	TranscribeModel string
	Timeout         time.Duration
}

// OpenAIProvider talks to the OpenAI API. Every call carries the request
// context, so a cancelled request or a request-timeout deadline aborts it.
type OpenAIProvider struct {
	cfg    OpenAIConfig
	client *http.Client
}

// NewOpenAIProvider builds a provider. An empty API key makes every call
// return ErrNotConfigured rather than failing at construction.
func NewOpenAIProvider(cfg OpenAIConfig) *OpenAIProvider {
	return &OpenAIProvider{cfg: cfg, client: &http.Client{Timeout: cfg.Timeout}}
}

// APIError is a non-2xx response from the provider.
type APIError struct {
	StatusCode int
	Detail     string
}

func (e *APIError) Error() string {
	if e.Detail == "" {
		return fmt.Sprintf("ai provider returned status %d", e.StatusCode)
	}
	return fmt.Sprintf("ai provider returned status %d: %s", e.StatusCode, e.Detail)
}

// Transcribe posts audio to the transcription endpoint.
func (p *OpenAIProvider) Transcribe(ctx context.Context, req TranscribeRequest) (string, error) {
	if p.cfg.APIKey == "" {
		return "", ErrNotConfigured
	}

	model := req.Model
	if model == "" {
		model = p.cfg.TranscribeModel
	}
	filename := req.Filename
	if filename == "" {
		filename = "audio.m4a"
	}

	// Stream the multipart body instead of buffering it: the audio bytes are
	// already in memory, and a bytes.Buffer would hold a second copy of them.
	pr, pw := io.Pipe()
	mw := multipart.NewWriter(pw)
	go func() {
		if err := writeTranscription(mw, model, filename, req.Prompt, req.Audio); err != nil {
			_ = pw.CloseWithError(err)
			return
		}
		_ = pw.Close()
	}()

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost,
		p.cfg.BaseURL+"/audio/transcriptions", pr)
	if err != nil {
		return "", fmt.Errorf("build transcription request: %w", err)
	}
	httpReq.Header.Set("Authorization", "Bearer "+p.cfg.APIKey)
	httpReq.Header.Set("Content-Type", mw.FormDataContentType())

	body, err := p.do(httpReq)
	if err != nil {
		return "", err
	}
	var out struct {
		Text string `json:"text"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		return "", fmt.Errorf("decode transcription response: %w", err)
	}
	return out.Text, nil
}

// writeTranscription writes the multipart fields and closes the writer. It runs
// in a goroutine feeding the request body pipe.
func writeTranscription(mw *multipart.Writer, model, filename, prompt string, audio []byte) error {
	if err := mw.WriteField("model", model); err != nil {
		return fmt.Errorf("build transcription request: %w", err)
	}
	if prompt != "" {
		if err := mw.WriteField("prompt", prompt); err != nil {
			return fmt.Errorf("build transcription request: %w", err)
		}
	}
	part, err := mw.CreateFormFile("file", filename)
	if err != nil {
		return fmt.Errorf("build transcription request: %w", err)
	}
	if _, err := part.Write(audio); err != nil {
		return fmt.Errorf("build transcription request: %w", err)
	}
	return mw.Close()
}

// Structured runs a chat completion constrained to a JSON schema and returns
// the object it produced.
func (p *OpenAIProvider) Structured(ctx context.Context, req StructuredRequest) (json.RawMessage, error) {
	if p.cfg.APIKey == "" {
		return nil, ErrNotConfigured
	}

	model := req.Model
	if model == "" {
		model = p.cfg.ParseModel
	}

	content, err := p.completion(ctx, model, []Message{
		{Role: "system", Content: req.SystemPrompt},
		{Role: "user", Content: req.UserContent},
	}, map[string]any{
		"type": "json_schema",
		"json_schema": map[string]any{
			"name":   req.SchemaName,
			"strict": true,
			"schema": req.Schema,
		},
	})
	if err != nil {
		return nil, err
	}

	raw := json.RawMessage(content)
	if !json.Valid(raw) {
		return nil, fmt.Errorf("provider returned invalid JSON")
	}
	return raw, nil
}

// Chat runs a free-form chat completion.
func (p *OpenAIProvider) Chat(ctx context.Context, req ChatRequest) (string, error) {
	if p.cfg.APIKey == "" {
		return "", ErrNotConfigured
	}

	model := req.Model
	if model == "" {
		model = p.cfg.ParseModel
	}

	messages := make([]Message, 0, len(req.Messages)+1)
	messages = append(messages, Message{Role: "system", Content: req.SystemPrompt})
	messages = append(messages, req.Messages...)

	return p.completion(ctx, model, messages, nil)
}

func (p *OpenAIProvider) completion(ctx context.Context, model string, messages []Message, responseFormat map[string]any) (string, error) {
	payload := map[string]any{
		"model":       model,
		"temperature": 0,
		"messages":    messages,
	}
	if responseFormat != nil {
		payload["response_format"] = responseFormat
	}

	encoded, err := json.Marshal(payload)
	if err != nil {
		return "", fmt.Errorf("encode completion request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost,
		p.cfg.BaseURL+"/chat/completions", bytes.NewReader(encoded))
	if err != nil {
		return "", fmt.Errorf("build completion request: %w", err)
	}
	httpReq.Header.Set("Authorization", "Bearer "+p.cfg.APIKey)
	httpReq.Header.Set("Content-Type", "application/json")

	body, err := p.do(httpReq)
	if err != nil {
		return "", err
	}

	var out struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		return "", fmt.Errorf("decode completion response: %w", err)
	}
	if len(out.Choices) == 0 {
		return "", fmt.Errorf("provider returned no choices")
	}
	return out.Choices[0].Message.Content, nil
}

func (p *OpenAIProvider) do(req *http.Request) ([]byte, error) {
	resp, err := p.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("call ai provider: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	body, err := io.ReadAll(io.LimitReader(resp.Body, maxProviderResponse))
	if err != nil {
		return nil, fmt.Errorf("read ai provider response: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, &APIError{StatusCode: resp.StatusCode, Detail: providerErrorMessage(body)}
	}
	return body, nil
}

// providerErrorMessage extracts the provider's own error message without
// echoing anything else from the response.
func providerErrorMessage(body []byte) string {
	var parsed struct {
		Error struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(body, &parsed); err == nil {
		return parsed.Error.Message
	}
	return ""
}
