package httpapi

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tedif/weight-buddy-backend/internal/site"
)

// TestSiteIsMountedWithoutShadowingAPI checks that the public site is served
// for non-API paths while /healthz and /v1/* keep behaving as API routes.
func TestSiteIsMountedWithoutShadowingAPI(t *testing.T) {
	router := NewRouter(Deps{Logger: testLogger(), Site: site.Handler()})

	serve := func(method, path string) *httptest.ResponseRecorder {
		t.Helper()
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, httptest.NewRequest(method, path, nil))
		return rec
	}

	t.Run("healthz unaffected", func(t *testing.T) {
		rec := serve(http.MethodGet, "/healthz")
		if rec.Code != http.StatusOK {
			t.Fatalf("status = %d, want 200", rec.Code)
		}
		if ct := rec.Header().Get("Content-Type"); ct != "application/json; charset=utf-8" {
			t.Fatalf("content-type = %q, want JSON", ct)
		}
	})

	t.Run("v1 me unaffected", func(t *testing.T) {
		rec := serve(http.MethodGet, "/v1/me")
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("status = %d, want 401", rec.Code)
		}
		if code := errorCode(t, rec); code != "unauthorized" {
			t.Fatalf("code = %q, want unauthorized", code)
		}
		if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "application/json") {
			t.Fatalf("content-type = %q, want JSON, not the site's HTML", ct)
		}
	})

	pages := []struct{ path, want string }{
		{"/privacy", "Privacy policy"},
		{"/terms", "Terms of service"},
		{"/delete-account", "Delete your account"},
	}
	for _, tc := range pages {
		t.Run(tc.path, func(t *testing.T) {
			rec := serve(http.MethodGet, tc.path)
			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200", rec.Code)
			}
			if body := rec.Body.String(); !strings.Contains(body, tc.want) {
				t.Fatalf("body does not contain %q", tc.want)
			}
		})
	}

	t.Run("unknown path is the site 404", func(t *testing.T) {
		rec := serve(http.MethodGet, "/nope")
		if rec.Code != http.StatusNotFound {
			t.Fatalf("status = %d, want 404", rec.Code)
		}
		if !strings.Contains(rec.Body.String(), "Page not found") {
			t.Fatal("expected the site 404 page")
		}
	})

	t.Run("unknown v1 path is JSON", func(t *testing.T) {
		rec := serve(http.MethodGet, "/v1/nope")
		if rec.Code != http.StatusNotFound {
			t.Fatalf("status = %d, want 404", rec.Code)
		}
		if code := errorCode(t, rec); code != "not_found" {
			t.Fatalf("code = %q, want not_found", code)
		}
	})
}
