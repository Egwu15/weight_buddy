package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestAppVersionIsPublicAndUncached(t *testing.T) {
	deps := Deps{
		Logger:            testLogger(),
		AppMinimumVersion: "1.2.3",
		AppStoreURL:       "https://play.google.com/store/apps/details?id=com.tedif.weight_buddy",
		AppUpdateMessage:  "Please update to continue.",
	}
	router := NewRouter(deps)

	req := httptest.NewRequest(http.MethodGet, "/v1/app/version", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	if cc := rec.Header().Get("Cache-Control"); cc != "no-store" {
		t.Fatalf("Cache-Control = %q, want no-store", cc)
	}

	var body appVersionResponse
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if body.MinimumVersion != "1.2.3" {
		t.Fatalf("minimum_version = %q, want 1.2.3", body.MinimumVersion)
	}
	if body.StoreURL != deps.AppStoreURL {
		t.Fatalf("store_url = %q, want %q", body.StoreURL, deps.AppStoreURL)
	}
	if body.Message != deps.AppUpdateMessage {
		t.Fatalf("message = %q, want %q", body.Message, deps.AppUpdateMessage)
	}
}
