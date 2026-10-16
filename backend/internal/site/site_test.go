package site

import (
	"io/fs"
	"net/http"
	"net/http/httptest"
	"path"
	"strings"
	"testing"

	webassets "github.com/tedif/weight-buddy-backend"
)

func get(t *testing.T, h http.Handler, path string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestServesPrerenderedPages(t *testing.T) {
	h := Handler()
	tests := []struct {
		path string
		want string
	}{
		{"/", "What it looks like"},
		{"/privacy", "Privacy policy"},
		{"/privacy/", "Privacy policy"},
		{"/terms", "Terms of service"},
		{"/delete-account", "Delete your account"},
	}
	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			rec := get(t, h, tt.path)
			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200", rec.Code)
			}
			if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/html") {
				t.Fatalf("content-type = %q, want text/html", ct)
			}
			if cc := rec.Header().Get("Cache-Control"); cc != "no-cache" {
				t.Fatalf("cache-control = %q, want no-cache", cc)
			}
			if body := rec.Body.String(); !strings.Contains(body, tt.want) {
				t.Fatalf("body does not contain %q", tt.want)
			}
		})
	}
}

func TestUnknownPathIs404PageNotIndex(t *testing.T) {
	h := Handler()
	for _, path := range []string{"/nope", "/privacy/extra", "/privacy/../secrets"} {
		t.Run(path, func(t *testing.T) {
			rec := get(t, h, path)
			if rec.Code != http.StatusNotFound {
				t.Fatalf("status = %d, want 404", rec.Code)
			}
			body := rec.Body.String()
			if !strings.Contains(body, "Page not found") {
				t.Fatalf("404 body is not the 404 page: %q", body)
			}
			// It must not be a soft fallback to the home page.
			if strings.Contains(body, "What it looks like") {
				t.Fatal("unknown path fell back to index.html")
			}
		})
	}
}

func TestHashedAssetsAreImmutable(t *testing.T) {
	h := Handler()
	assetsPath := "assets"
	sub, err := fs.Sub(webassets.Dist, "web/dist")
	if err != nil {
		t.Fatalf("sub fs: %v", err)
	}
	entries, err := fs.ReadDir(sub, assetsPath)
	if err != nil || len(entries) == 0 {
		t.Fatalf("no built assets found in dist/%s: %v", assetsPath, err)
	}
	name := entries[0].Name()

	rec := get(t, h, "/"+assetsPath+"/"+name)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if cc := rec.Header().Get("Cache-Control"); cc != "public, max-age=31536000, immutable" {
		t.Fatalf("cache-control = %q, want immutable", cc)
	}
}

// TestEveryPrerenderedPageResolves guards against the server's route list
// drifting from the built output: it walks the embedded build and asserts every
// pre-rendered page (any */index.html) is reachable through the handler.
func TestEveryPrerenderedPageResolves(t *testing.T) {
	h := Handler()
	sub, err := fs.Sub(webassets.Dist, "web/dist")
	if err != nil {
		t.Fatalf("sub fs: %v", err)
	}

	var routes []string
	err = fs.WalkDir(sub, ".", func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || d.Name() != "index.html" {
			return nil
		}
		dir := path.Dir(p)
		if dir == "." {
			routes = append(routes, "/")
		} else {
			routes = append(routes, "/"+dir)
		}
		return nil
	})
	if err != nil {
		t.Fatalf("walk dist: %v", err)
	}
	if len(routes) < 2 {
		t.Fatalf("expected several prerendered pages, found %v", routes)
	}

	for _, route := range routes {
		rec := get(t, h, route)
		if rec.Code != http.StatusOK {
			t.Errorf("%s -> status %d, want 200", route, rec.Code)
		}
	}
}

func TestRevalidatesHTMLWithETag(t *testing.T) {
	h := Handler()
	first := get(t, h, "/privacy")
	etag := first.Header().Get("Etag")
	if etag == "" {
		t.Fatal("no ETag on HTML response")
	}

	req := httptest.NewRequest(http.MethodGet, "/privacy", nil)
	req.Header.Set("If-None-Match", etag)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotModified {
		t.Fatalf("status = %d, want 304 with matching ETag", rec.Code)
	}
}

func TestRejectsNonGET(t *testing.T) {
	h := Handler()
	req := httptest.NewRequest(http.MethodPost, "/privacy", nil)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want 405", rec.Code)
	}
}
