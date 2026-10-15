package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/tedif/weight-buddy-backend/internal/ai"
	"github.com/tedif/weight-buddy-backend/internal/limits"
)

func aiDeps(t *testing.T, fs *fakeStore, provider ai.Provider) (Deps, string) {
	t.Helper()
	deps := testAuthDeps(fs)
	deps.Limits = &limits.Enforcer{Store: fs, Config: limits.Default(), SpendCap: 100}
	deps.Provider = provider

	user, _, err := fs.CreateOrGetUser(context.Background(), "device-12345678")
	if err != nil {
		t.Fatalf("seed user: %v", err)
	}
	token, err := deps.Tokens.Issue(user.ID)
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}
	return deps, token
}

func postAuth(t *testing.T, router http.Handler, token, path, contentType string, body []byte) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	return rec
}

func TestParseMealProxiesStructuredResponse(t *testing.T) {
	fs := newFakeStore()
	provider := &ai.FakeProvider{
		StructuredFunc: func(_ context.Context, _ ai.StructuredRequest) (json.RawMessage, error) {
			return json.RawMessage(`{"entry_type":"meal","summary":"Jollof rice"}`), nil
		},
	}
	deps, token := aiDeps(t, fs, provider)
	router := NewRouter(deps)

	rec := postAuth(t, router, token, "/v1/ai/parse-meal", "application/json",
		[]byte(`{"transcript":"I had jollof rice"}`))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	if !json.Valid(rec.Body.Bytes()) || !bytes.Contains(rec.Body.Bytes(), []byte(`"entry_type":"meal"`)) {
		t.Fatalf("unexpected body: %s", rec.Body.String())
	}

	calls := provider.StructuredCalls()
	if len(calls) != 1 {
		t.Fatalf("structured calls = %d, want 1", len(calls))
	}
	if !bytes.Contains([]byte(calls[0].SystemPrompt), []byte(`entry_type to "meal"`)) {
		t.Fatalf("system prompt did not bias entry_type: %q", calls[0].SystemPrompt)
	}
	if string(calls[0].Schema) != string(ai.ParseSchema) {
		t.Fatal("handler did not pass the parse schema")
	}

	user, _ := fs.UserByInstallID(context.Background(), "device-12345678")
	if fs.usage[user.ID+"|"+string(limits.KindParseMeal)] != 1 {
		t.Fatal("expected one parse_meal usage unit recorded")
	}
}

func TestParseExerciseIsMeteredSeparately(t *testing.T) {
	fs := newFakeStore()
	provider := &ai.FakeProvider{}
	deps, token := aiDeps(t, fs, provider)
	router := NewRouter(deps)

	rec := postAuth(t, router, token, "/v1/ai/parse-exercise", "application/json",
		[]byte(`{"transcript":"20 push ups"}`))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	calls := provider.StructuredCalls()
	if len(calls) != 1 || !bytes.Contains([]byte(calls[0].SystemPrompt), []byte(`entry_type to "exercise"`)) {
		t.Fatalf("expected an exercise-biased prompt, got %+v", calls)
	}
	user, _ := fs.UserByInstallID(context.Background(), "device-12345678")
	if fs.usage[user.ID+"|"+string(limits.KindParseExercise)] != 1 {
		t.Fatal("expected one parse_exercise usage unit recorded")
	}
}

func TestTranscribeAcceptsMultipartUpload(t *testing.T) {
	fs := newFakeStore()
	provider := &ai.FakeProvider{}
	deps, token := aiDeps(t, fs, provider)
	router := NewRouter(deps)

	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	part, _ := mw.CreateFormFile("file", "note.m4a")
	_, _ = part.Write([]byte("fake-audio-bytes"))
	_ = mw.WriteField("prompt", "Jollof, Egusi")
	_ = mw.Close()

	rec := postAuth(t, router, token, "/v1/ai/transcribe", mw.FormDataContentType(), buf.Bytes())
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if body["text"] != "transcribed text" {
		t.Fatalf("text = %q", body["text"])
	}

	calls := provider.TranscribeCalls()
	if len(calls) != 1 || calls[0].Prompt != "Jollof, Egusi" || len(calls[0].Audio) == 0 {
		t.Fatalf("unexpected transcribe call: %+v", calls)
	}
}

func TestChatReturnsReply(t *testing.T) {
	fs := newFakeStore()
	provider := &ai.FakeProvider{
		ChatFunc: func(_ context.Context, _ ai.ChatRequest) (string, error) { return "drink water", nil },
	}
	deps, token := aiDeps(t, fs, provider)
	router := NewRouter(deps)

	rec := postAuth(t, router, token, "/v1/ai/chat", "application/json",
		[]byte(`{"system_prompt":"be a coach","messages":[{"role":"user","content":"hi"}]}`))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	var body map[string]string
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body["reply"] != "drink water" {
		t.Fatalf("reply = %q", body["reply"])
	}
}

func TestAIEnforcesUserLimit(t *testing.T) {
	fs := newFakeStore()
	deps, token := aiDeps(t, fs, &ai.FakeProvider{})
	router := NewRouter(deps)

	user, _ := fs.UserByInstallID(context.Background(), "device-12345678")
	fs.usage[user.ID+"|"+string(limits.KindTranscribe)] = 10 // free limit is 10

	rec := postAuth(t, router, token, "/v1/ai/transcribe", "application/json", []byte(`{}`))
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("status = %d, want 429 (%s)", rec.Code, rec.Body.String())
	}
	if code := errorCode(t, rec); code != "limit_reached" {
		t.Fatalf("code = %q, want limit_reached", code)
	}
}

func TestAIEnforcesSpendCap(t *testing.T) {
	fs := newFakeStore()
	deps, token := aiDeps(t, fs, &ai.FakeProvider{})
	deps.Limits.SpendCap = 1
	router := NewRouter(deps)

	fs.spend = 2
	rec := postAuth(t, router, token, "/v1/ai/chat", "application/json",
		[]byte(`{"system_prompt":"x","messages":[{"role":"user","content":"hi"}]}`))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503 (%s)", rec.Code, rec.Body.String())
	}
	if code := errorCode(t, rec); code != "spend_cap" {
		t.Fatalf("code = %q, want spend_cap", code)
	}
}

func TestAIProviderErrorIsFriendly(t *testing.T) {
	fs := newFakeStore()
	provider := &ai.FakeProvider{
		StructuredFunc: func(_ context.Context, _ ai.StructuredRequest) (json.RawMessage, error) {
			return nil, &ai.APIError{StatusCode: 500, Detail: "boom"}
		},
	}
	deps, token := aiDeps(t, fs, provider)
	router := NewRouter(deps)

	rec := postAuth(t, router, token, "/v1/ai/parse-meal", "application/json",
		[]byte(`{"transcript":"jollof"}`))
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("status = %d, want 502 (%s)", rec.Code, rec.Body.String())
	}
	if code := errorCode(t, rec); code != "ai_unavailable" {
		t.Fatalf("code = %q, want ai_unavailable", code)
	}
}

func TestAIWithoutProviderIs503(t *testing.T) {
	fs := newFakeStore()
	deps, token := aiDeps(t, fs, nil) // no provider configured
	router := NewRouter(deps)

	rec := postAuth(t, router, token, "/v1/ai/parse-meal", "application/json",
		[]byte(`{"transcript":"jollof"}`))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", rec.Code)
	}
	if code := errorCode(t, rec); code != "not_configured" {
		t.Fatalf("code = %q, want not_configured", code)
	}
}

func TestAIRequiresAuth(t *testing.T) {
	fs := newFakeStore()
	deps, _ := aiDeps(t, fs, &ai.FakeProvider{})
	router := NewRouter(deps)

	req := httptest.NewRequest(http.MethodPost, "/v1/ai/parse-meal", bytes.NewReader([]byte(`{}`)))
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}
