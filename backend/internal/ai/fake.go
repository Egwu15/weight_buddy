package ai

import (
	"context"
	"encoding/json"
	"sync"
)

// FakeProvider is an in-memory Provider for tests. Each method delegates to an
// optional func, or returns a fixed canned value, and records every call so
// tests can assert on what the handlers passed through.
type FakeProvider struct {
	TranscribeFunc func(ctx context.Context, req TranscribeRequest) (string, error)
	StructuredFunc func(ctx context.Context, req StructuredRequest) (json.RawMessage, error)
	ChatFunc       func(ctx context.Context, req ChatRequest) (string, error)

	mu              sync.Mutex
	transcribeCalls []TranscribeRequest
	structuredCalls []StructuredRequest
	chatCalls       []ChatRequest
}

// Transcribe records and serves a transcription.
func (f *FakeProvider) Transcribe(ctx context.Context, req TranscribeRequest) (string, error) {
	f.mu.Lock()
	f.transcribeCalls = append(f.transcribeCalls, req)
	f.mu.Unlock()
	if f.TranscribeFunc != nil {
		return f.TranscribeFunc(ctx, req)
	}
	return "transcribed text", nil
}

// Structured records and serves a structured completion.
func (f *FakeProvider) Structured(ctx context.Context, req StructuredRequest) (json.RawMessage, error) {
	f.mu.Lock()
	f.structuredCalls = append(f.structuredCalls, req)
	f.mu.Unlock()
	if f.StructuredFunc != nil {
		return f.StructuredFunc(ctx, req)
	}
	return json.RawMessage(`{"ok":true}`), nil
}

// Chat records and serves a chat completion.
func (f *FakeProvider) Chat(ctx context.Context, req ChatRequest) (string, error) {
	f.mu.Lock()
	f.chatCalls = append(f.chatCalls, req)
	f.mu.Unlock()
	if f.ChatFunc != nil {
		return f.ChatFunc(ctx, req)
	}
	return "coach reply", nil
}

// TranscribeCalls returns the recorded transcription requests.
func (f *FakeProvider) TranscribeCalls() []TranscribeRequest {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]TranscribeRequest(nil), f.transcribeCalls...)
}

// StructuredCalls returns the recorded structured requests.
func (f *FakeProvider) StructuredCalls() []StructuredRequest {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]StructuredRequest(nil), f.structuredCalls...)
}

// ChatCalls returns the recorded chat requests.
func (f *FakeProvider) ChatCalls() []ChatRequest {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]ChatRequest(nil), f.chatCalls...)
}
