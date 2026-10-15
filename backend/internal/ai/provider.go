// Package ai defines the swappable AI provider interface and the proxy
// handlers that call it on the app's behalf. The provider key never leaves the
// backend.
package ai

import (
	"context"
	"encoding/json"
	"errors"
)

// ErrNotConfigured is returned when the provider has no credentials.
var ErrNotConfigured = errors.New("ai: provider is not configured")

// Message is one turn in a chat conversation.
type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// TranscribeRequest is an audio transcription job.
type TranscribeRequest struct {
	Audio    []byte
	Filename string
	// Prompt biases recognition toward a custom vocabulary.
	Prompt string
	Model  string
}

// StructuredRequest asks for a single JSON object conforming to Schema. The
// provider must return exactly that object.
type StructuredRequest struct {
	SystemPrompt string
	UserContent  string
	SchemaName   string
	Schema       json.RawMessage
	Model        string
}

// ChatRequest is a free-form conversation.
type ChatRequest struct {
	SystemPrompt string
	Messages     []Message
	Model        string
}

// Provider is the AI vendor seam. Swapping vendors means implementing this
// interface and nothing else.
type Provider interface {
	// Transcribe turns audio into text.
	Transcribe(ctx context.Context, req TranscribeRequest) (string, error)
	// Structured returns a JSON object matching the requested schema.
	Structured(ctx context.Context, req StructuredRequest) (json.RawMessage, error)
	// Chat returns the assistant's reply.
	Chat(ctx context.Context, req ChatRequest) (string, error)
}
