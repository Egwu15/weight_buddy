package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/tedif/weight-buddy-backend/internal/auth"
)

func testAuthDeps(fs *fakeStore) Deps {
	return Deps{
		Logger:                testLogger(),
		Store:                 fs,
		Tokens:                auth.NewTokens("test-secret", time.Hour),
		JWTSecret:             "test-secret",
		FreeAccountsPerDevice: 1,
	}
}

func postAnonymous(t *testing.T, router http.Handler, body, remoteAddr string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/v1/auth/anonymous", strings.NewReader(body))
	req.RemoteAddr = remoteAddr
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	return rec
}

func TestAnonymousSignInIssuesToken(t *testing.T) {
	fs := newFakeStore()
	deps := testAuthDeps(fs)
	router := NewRouter(deps)

	rec := postAnonymous(t, router, `{"install_id":"device-12345678"}`, "1.2.3.4:5555")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}

	var body anonymousResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if body.UserID == "" || body.Token == "" {
		t.Fatalf("empty response: %+v", body)
	}

	gotID, err := deps.Tokens.Verify(body.Token)
	if err != nil {
		t.Fatalf("issued token does not verify: %v", err)
	}
	if gotID != body.UserID {
		t.Fatalf("token subject %q != user_id %q", gotID, body.UserID)
	}
}

func TestAnonymousSignInIsStablePerDevice(t *testing.T) {
	fs := newFakeStore()
	router := NewRouter(testAuthDeps(fs))

	first := postAnonymous(t, router, `{"install_id":"device-12345678"}`, "1.2.3.4:5555")
	second := postAnonymous(t, router, `{"install_id":"device-12345678"}`, "9.9.9.9:5555")

	if first.Code != http.StatusOK || second.Code != http.StatusOK {
		t.Fatalf("statuses = %d, %d; want both 200", first.Code, second.Code)
	}
	var a, b anonymousResponse
	_ = json.Unmarshal(first.Body.Bytes(), &a)
	_ = json.Unmarshal(second.Body.Bytes(), &b)
	if a.UserID != b.UserID {
		t.Fatalf("same device got different users: %q vs %q", a.UserID, b.UserID)
	}
}

func TestAnonymousRejectsMalformedRequest(t *testing.T) {
	fs := newFakeStore()
	router := NewRouter(testAuthDeps(fs))

	tests := []struct {
		name string
		body string
	}{
		{"not json", `not json`},
		{"missing install id", `{}`},
		{"install id too short", `{"install_id":"short"}`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := postAnonymous(t, router, tt.body, "1.2.3.4:5555")
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400 (%s)", rec.Code, rec.Body.String())
			}
			if code := errorCode(t, rec); code != "invalid_request" {
				t.Fatalf("code = %q, want invalid_request", code)
			}
		})
	}
}

func TestAnonymousEnforcesDeviceCap(t *testing.T) {
	fs := newFakeStore()
	router := NewRouter(testAuthDeps(fs)) // cap is 1 per device

	first := postAnonymous(t, router, `{"install_id":"device-aaaaaaaa"}`, "1.2.3.4:5555")
	if first.Code != http.StatusOK {
		t.Fatalf("first sign-in status = %d, want 200", first.Code)
	}

	second := postAnonymous(t, router, `{"install_id":"device-bbbbbbbb"}`, "1.2.3.4:5555")
	if second.Code != http.StatusTooManyRequests {
		t.Fatalf("second sign-in from same device = %d, want 429", second.Code)
	}
	if code := errorCode(t, second); code != "device_limit" {
		t.Fatalf("code = %q, want device_limit", code)
	}
}

func TestRequireAuth(t *testing.T) {
	fs := newFakeStore()
	deps := testAuthDeps(fs)
	if _, _, err := fs.CreateOrGetUser(t.Context(), "device-12345678"); err != nil {
		t.Fatalf("seed user: %v", err)
	}
	token, err := deps.Tokens.Issue("user-device-12345678")
	if err != nil {
		t.Fatalf("issue: %v", err)
	}

	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		u, ok := userFromContext(r.Context())
		if !ok {
			t.Error("expected user in context")
		}
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(map[string]string{"install_id": u.InstallID})
	})
	handler := deps.requireAuth(next)

	tests := []struct {
		name       string
		authHeader string
		wantStatus int
	}{
		{"missing header", "", http.StatusUnauthorized},
		{"not bearer", "Token abc", http.StatusUnauthorized},
		{"garbage token", "Bearer garbage", http.StatusUnauthorized},
		{"valid", "Bearer " + token, http.StatusOK},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/v1/me", nil)
			if tt.authHeader != "" {
				req.Header.Set("Authorization", tt.authHeader)
			}
			rec := httptest.NewRecorder()
			handler.ServeHTTP(rec, req)
			if rec.Code != tt.wantStatus {
				t.Fatalf("status = %d, want %d (%s)", rec.Code, tt.wantStatus, rec.Body.String())
			}
		})
	}
}

// errorCode extracts the standard {"error":{"code":...}} code from a response.
func errorCode(t *testing.T, rec *httptest.ResponseRecorder) string {
	t.Helper()
	var body apiError
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode error body: %v (%s)", err, rec.Body.String())
	}
	return body.Error.Code
}
