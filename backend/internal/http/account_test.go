package httpapi

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/tedif/weight-buddy-backend/internal/store"
)

func deleteMe(t *testing.T, router http.Handler, token string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodDelete, "/v1/me", nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	return rec
}

func TestDeleteMeRemovesEverything(t *testing.T) {
	fs := newFakeStore()
	deps := testAuthDeps(fs)
	router := NewRouter(deps)

	user, token := seedAnonymous(t, fs, deps, "device-delete-1")
	// Give the account data that must go with it.
	fs.entitlements[user.ID] = store.Entitlement{
		UserID: user.ID, Entitlement: "pro", Status: "active",
	}
	if err := fs.RecordUsage(t.Context(), user.ID, "transcribe", 3, 0.02); err != nil {
		t.Fatalf("seed usage: %v", err)
	}

	rec := deleteMe(t, router, token)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204 (%s)", rec.Code, rec.Body.String())
	}

	if _, found := fs.users["device-delete-1"]; found {
		t.Fatal("user row still present after deletion")
	}
	if _, found := fs.entitlements[user.ID]; found {
		t.Fatal("entitlement row still present after deletion")
	}
	if got := fs.usage[user.ID+"|transcribe"]; got != 0 {
		t.Fatalf("usage row still present after deletion: %v", got)
	}
}

func TestDeleteMeIsIdempotent(t *testing.T) {
	fs := newFakeStore()
	deps := testAuthDeps(fs)
	router := NewRouter(deps)

	_, token := seedAnonymous(t, fs, deps, "device-delete-2")

	first := deleteMe(t, router, token)
	if first.Code != http.StatusNoContent {
		t.Fatalf("first delete = %d, want 204", first.Code)
	}
	// The token is still valid; a retry must settle, not 401.
	second := deleteMe(t, router, token)
	if second.Code != http.StatusNoContent {
		t.Fatalf("second delete = %d, want 204 (%s)", second.Code, second.Body.String())
	}
}

func TestDeleteMeRequiresAuth(t *testing.T) {
	fs := newFakeStore()
	router := NewRouter(testAuthDeps(fs))

	tests := []struct {
		name  string
		token string
	}{
		{"missing token", ""},
		{"garbage token", "not-a-real-token"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := deleteMe(t, router, tt.token)
			if rec.Code != http.StatusUnauthorized {
				t.Fatalf("status = %d, want 401 (%s)", rec.Code, rec.Body.String())
			}
			if code := errorCode(t, rec); code != "unauthorized" {
				t.Fatalf("code = %q, want unauthorized", code)
			}
		})
	}
}
