package ai

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func testProvider(t *testing.T, handler http.HandlerFunc) (*OpenAIProvider, *httptest.Server) {
	t.Helper()
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)
	return NewOpenAIProvider(OpenAIConfig{
		APIKey:          "test-key",
		BaseURL:         srv.URL,
		ParseModel:      "gpt-4o-mini",
		TranscribeModel: "gpt-transcribe",
		Timeout:         2 * time.Second,
	}), srv
}

func TestOpenAITranscribe(t *testing.T) {
	var contentLength int64
	p, _ := testProvider(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/audio/transcriptions" {
			t.Errorf("path = %q", r.URL.Path)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-key" {
			t.Errorf("authorization = %q", got)
		}
		if err := r.ParseMultipartForm(1 << 20); err != nil {
			t.Errorf("parse multipart: %v", err)
		}
		if _, _, err := r.FormFile("file"); err != nil {
			t.Errorf("missing file field: %v", err)
		}
		contentLength = r.ContentLength
		_ = json.NewEncoder(w).Encode(map[string]string{"text": "hello world"})
	})

	got, err := p.Transcribe(context.Background(), TranscribeRequest{
		Audio:    []byte("audio-bytes"),
		Filename: "note.m4a",
		Prompt:   "Jollof",
	})
	if err != nil {
		t.Fatalf("transcribe: %v", err)
	}
	if got != "hello world" {
		t.Fatalf("text = %q", got)
	}
	if contentLength <= 0 {
		t.Fatal("expected a request body")
	}
}

func TestOpenAIStructured(t *testing.T) {
	var gotBody map[string]any
	p, _ := testProvider(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/chat/completions" {
			t.Errorf("path = %q", r.URL.Path)
		}
		_ = json.NewDecoder(r.Body).Decode(&gotBody)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"choices": []map[string]any{
				{"message": map[string]string{"content": `{"entry_type":"meal"}`}},
			},
		})
	})

	raw, err := p.Structured(context.Background(), StructuredRequest{
		SystemPrompt: "sys",
		UserContent:  "user",
		SchemaName:   "food_exercise_log",
		Schema:       json.RawMessage(`{"type":"object"}`),
	})
	if err != nil {
		t.Fatalf("structured: %v", err)
	}
	if string(raw) != `{"entry_type":"meal"}` {
		t.Fatalf("raw = %s", raw)
	}

	rf, ok := gotBody["response_format"].(map[string]any)
	if !ok || rf["type"] != "json_schema" {
		t.Fatalf("missing json_schema response_format: %+v", gotBody["response_format"])
	}
	if gotBody["model"] != "gpt-4o-mini" {
		t.Fatalf("model = %v", gotBody["model"])
	}
}

func TestOpenAIChat(t *testing.T) {
	p, _ := testProvider(t, func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{
			"choices": []map[string]any{
				{"message": map[string]string{"content": "coach says hi"}},
			},
		})
	})

	got, err := p.Chat(context.Background(), ChatRequest{
		SystemPrompt: "sys",
		Messages:     []Message{{Role: "user", Content: "hi"}},
	})
	if err != nil {
		t.Fatalf("chat: %v", err)
	}
	if got != "coach says hi" {
		t.Fatalf("reply = %q", got)
	}
}

func TestOpenAIErrorStatus(t *testing.T) {
	p, _ := testProvider(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"error": map[string]string{"message": "invalid api key"},
		})
	})

	_, err := p.Chat(context.Background(), ChatRequest{SystemPrompt: "s", Messages: []Message{{Role: "user", Content: "x"}}})
	var apiErr *APIError
	if !errors.As(err, &apiErr) {
		t.Fatalf("err = %v, want *APIError", err)
	}
	if apiErr.StatusCode != http.StatusUnauthorized || apiErr.Detail != "invalid api key" {
		t.Fatalf("apiErr = %+v", apiErr)
	}
}

func TestOpenAIInvalidJSONFails(t *testing.T) {
	p, _ := testProvider(t, func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{
			"choices": []map[string]any{
				{"message": map[string]string{"content": "not json"}},
			},
		})
	})
	if _, err := p.Structured(context.Background(), StructuredRequest{SystemPrompt: "s", UserContent: "u"}); err == nil {
		t.Fatal("expected an error for a non-JSON structured response")
	}
}

func TestOpenAINotConfigured(t *testing.T) {
	p := NewOpenAIProvider(OpenAIConfig{BaseURL: "http://localhost", Timeout: time.Second})
	if _, err := p.Chat(context.Background(), ChatRequest{}); !errors.Is(err, ErrNotConfigured) {
		t.Fatalf("err = %v, want ErrNotConfigured", err)
	}
}
