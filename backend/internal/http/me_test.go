package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/tedif/weight-buddy-backend/internal/limits"
	"github.com/tedif/weight-buddy-backend/internal/store"
)

func meDeps(t *testing.T, fs *fakeStore) (Deps, string) {
	t.Helper()
	deps := testAuthDeps(fs)
	deps.Limits = &limits.Enforcer{Store: fs, Config: limits.Default(), SpendCap: 25}

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

func getMe(t *testing.T, router http.Handler, token string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/v1/me", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	return rec
}

func TestMeRequiresAuth(t *testing.T) {
	fs := newFakeStore()
	deps, _ := meDeps(t, fs)
	router := NewRouter(deps)

	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/me", nil))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}

func TestMeFreeTier(t *testing.T) {
	fs := newFakeStore()
	deps, token := meDeps(t, fs)
	router := NewRouter(deps)

	rec := getMe(t, router, token)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}

	var body meResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if body.Tier != "free" || body.Entitlement != nil {
		t.Fatalf("free user view = %+v", body)
	}
	if len(body.Limits) == 0 {
		t.Fatal("expected per-kind limits")
	}
	if body.SpendRemainingUSD != 25 {
		t.Fatalf("spend remaining = %v, want 25", body.SpendRemainingUSD)
	}
	for _, ku := range body.Limits {
		if ku.Kind == string(limits.KindTranscribe) && ku.Remaining != 10 {
			t.Fatalf("free transcribe remaining = %d, want 10", ku.Remaining)
		}
	}
}

func TestMePaidTierAndUsage(t *testing.T) {
	fs := newFakeStore()
	deps, token := meDeps(t, fs)
	router := NewRouter(deps)

	user, _, _ := fs.CreateOrGetUser(context.Background(), "device-12345678")
	fs.entitlements[user.ID] = store.Entitlement{UserID: user.ID, Entitlement: "pro", Status: "active"}
	fs.usage[user.ID+"|"+string(limits.KindTranscribe)] = 12

	rec := getMe(t, router, token)
	var body meResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if body.Tier != "paid" {
		t.Fatalf("tier = %q, want paid", body.Tier)
	}
	if body.Entitlement == nil || !body.Entitlement.IsActive {
		t.Fatalf("entitlement = %+v, want active", body.Entitlement)
	}
	for _, ku := range body.Limits {
		if ku.Kind == string(limits.KindTranscribe) {
			if ku.Limit != 300 || ku.Used != 12 || ku.Remaining != 288 {
				t.Fatalf("paid transcribe = %+v, want 12 used of 300", ku)
			}
		}
	}
}
