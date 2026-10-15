package httpapi

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/tedif/weight-buddy-backend/internal/store"
)

const (
	testWebhookSecret = "whsec-test"
	testUserID        = "11111111-1111-1111-1111-111111111111"
)

func webhookDeps(fs *fakeStore) Deps {
	return Deps{
		Logger:                  testLogger(),
		Store:                   fs,
		RevenueCatWebhookSecret: testWebhookSecret,
		RevenueCatEntitlementID: "pro",
	}
}

func seedUser(fs *fakeStore) {
	fs.users["seed"] = store.User{ID: testUserID, InstallID: "seed"}
}

func postWebhook(t *testing.T, router http.Handler, fixture, secret string) *httptest.ResponseRecorder {
	t.Helper()
	body, err := os.ReadFile(filepath.Join("testdata", fixture))
	if err != nil {
		t.Fatalf("read fixture %s: %v", fixture, err)
	}
	req := httptest.NewRequest(http.MethodPost, "/v1/webhooks/revenuecat", bytes.NewReader(body))
	req.Header.Set("Authorization", secret)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	return rec
}

func webhookStatus(t *testing.T, rec *httptest.ResponseRecorder) string {
	t.Helper()
	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v (%s)", err, rec.Body.String())
	}
	return body["status"]
}

func TestRevenueCatWebhookGrantsEntitlement(t *testing.T) {
	fs := newFakeStore()
	seedUser(fs)
	router := NewRouter(webhookDeps(fs))

	rec := postWebhook(t, router, "initial_purchase.json", testWebhookSecret)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	if got := webhookStatus(t, rec); got != "ok" {
		t.Fatalf("status field = %q, want ok", got)
	}

	e, ok := fs.entitlements[testUserID]
	if !ok {
		t.Fatal("expected an entitlement row")
	}
	if e.Status != "active" || e.Entitlement != "pro" {
		t.Fatalf("entitlement = %+v, want active/pro", e)
	}
	if e.ExpiresAt == nil {
		t.Fatal("expected an expiry from expiration_at_ms")
	}
}

func TestRevenueCatWebhookIsIdempotent(t *testing.T) {
	fs := newFakeStore()
	seedUser(fs)
	router := NewRouter(webhookDeps(fs))

	first := postWebhook(t, router, "initial_purchase.json", testWebhookSecret)
	if got := webhookStatus(t, first); got != "ok" {
		t.Fatalf("first status = %q, want ok", got)
	}

	// A retry of the same event id must be acknowledged but not re-applied.
	fs.entitlements[testUserID] = store.Entitlement{UserID: testUserID, Status: "expired"}
	second := postWebhook(t, router, "initial_purchase.json", testWebhookSecret)
	if got := webhookStatus(t, second); got != "duplicate" {
		t.Fatalf("second status = %q, want duplicate", got)
	}
	if fs.entitlements[testUserID].Status != "expired" {
		t.Fatal("duplicate delivery must not overwrite entitlement state")
	}
}

func TestRevenueCatWebhookRejectsBadSecret(t *testing.T) {
	fs := newFakeStore()
	seedUser(fs)
	router := NewRouter(webhookDeps(fs))

	rec := postWebhook(t, router, "initial_purchase.json", "wrong-secret")
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}

func TestRevenueCatWebhookRejectsBadJSON(t *testing.T) {
	fs := newFakeStore()
	router := NewRouter(webhookDeps(fs))

	req := httptest.NewRequest(http.MethodPost, "/v1/webhooks/revenuecat", bytes.NewReader([]byte("not json")))
	req.Header.Set("Authorization", testWebhookSecret)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
}

func TestRevenueCatWebhookLifecycleMappings(t *testing.T) {
	tests := []struct {
		fixture    string
		wantStatus string
		wantChange bool
	}{
		{"cancellation.json", "cancelled_active", true},
		{"expiration.json", "expired", true},
		{"billing_issue.json", "grace", true},
		{"transfer.json", "", false},
	}
	for _, tt := range tests {
		t.Run(tt.fixture, func(t *testing.T) {
			fs := newFakeStore()
			seedUser(fs)
			router := NewRouter(webhookDeps(fs))

			rec := postWebhook(t, router, tt.fixture, testWebhookSecret)
			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
			}

			e, ok := fs.entitlements[testUserID]
			if !tt.wantChange {
				if ok {
					t.Fatalf("expected no entitlement change, got %+v", e)
				}
				return
			}
			if !ok {
				t.Fatal("expected an entitlement row")
			}
			if e.Status != tt.wantStatus {
				t.Fatalf("status = %q, want %q", e.Status, tt.wantStatus)
			}
		})
	}
}

func TestRevenueCatWebhookUnknownUserIsAcknowledged(t *testing.T) {
	fs := newFakeStore() // no user seeded
	router := NewRouter(webhookDeps(fs))

	rec := postWebhook(t, router, "initial_purchase.json", testWebhookSecret)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if got := webhookStatus(t, rec); got != "unknown_user" {
		t.Fatalf("status field = %q, want unknown_user", got)
	}
}
