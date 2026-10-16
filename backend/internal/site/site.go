// Package site serves the public website (home, privacy policy, terms of
// service and account deletion) straight from the Go binary.
//
// The pages are pre-rendered to real HTML at build time, so every route is
// readable with JavaScript disabled; the bundled JS only hydrates. The handler
// serves exact file matches and route directories, and never falls back to
// index.html, so an unknown path is a real 404 rather than a soft redirect to
// the home page.
package site

import (
	"bytes"
	"fmt"
	"hash/fnv"
	"io"
	"io/fs"
	"net/http"
	"path"
	"strings"
	"sync"
	"time"

	webassets "github.com/tedif/weight-buddy-backend"
)

// Handler returns the http.Handler for the embedded site. It is meant to be
// mounted as the router's not-found fallback, so the API always wins.
func Handler() http.Handler {
	sub, err := fs.Sub(webassets.Dist, "web/dist")
	if err != nil {
		// The embed directive guarantees web/dist exists at build time.
		panic("site: embedded assets are missing web/dist: " + err.Error())
	}
	return &handler{fsys: sub}
}

type handler struct {
	fsys fs.FS
	// cache holds each embedded file's bytes so a repeated request for a large
	// asset reuses one copy instead of re-reading it from the embedded image.
	// sync.Map's zero value is ready to use.
	cache sync.Map // name -> []byte
}

func (h *handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	name, ok := h.resolve(r.URL.Path)
	if !ok {
		h.notFound(w, r)
		return
	}
	h.serveFile(w, r, name)
}

// resolve maps a request path to a file in the embedded build. An exact file
// wins (hashed assets, favicon); otherwise the path is treated as a route
// directory with an index.html, so any page the build emits is served without
// a hand-maintained list to keep in sync. It returns false for no match, which
// the caller turns into a 404.
func (h *handler) resolve(urlPath string) (string, bool) {
	// Prefixing with "/" before Clean collapses every ".." segment, so the
	// cleaned path can never climb out of the embedded root.
	clean := path.Clean("/" + urlPath)
	name := strings.TrimPrefix(clean, "/")
	if name == "" {
		return "index.html", true
	}
	if h.isFile(name) {
		return name, true
	}
	if candidate := name + "/index.html"; h.isFile(candidate) {
		return candidate, true
	}
	return "", false
}

// isFile reports whether name is a file (not a directory) in the embedded FS.
func (h *handler) isFile(name string) bool {
	info, err := fs.Stat(h.fsys, name)
	return err == nil && !info.IsDir()
}

// serveFile writes an embedded file with a cache policy suited to its kind and
// a stable validator so revalidated pages can answer 304.
func (h *handler) serveFile(w http.ResponseWriter, r *http.Request, name string) {
	data, err := h.read(name)
	if err != nil {
		h.notFound(w, r)
		return
	}
	w.Header().Set("Cache-Control", cacheControl(name))
	w.Header().Set("Etag", etag(name, len(data)))
	// ServeContent sets the content type from the extension, handles HEAD and
	// supports range requests for the asset bundle.
	http.ServeContent(w, r, name, time.Time{}, bytes.NewReader(data))
}

// read returns an embedded file's bytes, reading them once and then serving the
// cached copy. The build is immutable, so the bytes never change at runtime.
func (h *handler) read(name string) ([]byte, error) {
	if cached, ok := h.cache.Load(name); ok {
		return cached.([]byte), nil
	}
	data, err := fs.ReadFile(h.fsys, name)
	if err != nil {
		return nil, err
	}
	actual, _ := h.cache.LoadOrStore(name, data)
	return actual.([]byte), nil
}

// etag derives a stable validator for an embedded file from its path and size,
// so it changes whenever the file is rebuilt.
func etag(name string, size int) string {
	sum := fnv.New64a()
	_, _ = io.WriteString(sum, name)
	_, _ = fmt.Fprintf(sum, ":%d", size)
	return fmt.Sprintf("\"%x\"", sum.Sum64())
}

// notFound renders the pre-rendered 404 page with a 404 status. It never falls
// back to index.html, so a missing page reads as missing to crawlers too.
func (h *handler) notFound(w http.ResponseWriter, _ *http.Request) {
	data, err := h.read("404.html")
	if err != nil {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-cache")
	w.WriteHeader(http.StatusNotFound)
	_, _ = w.Write(data)
}

// cacheControl gives hashed Vite assets a long immutable cache, HTML a
// revalidating one, and everything else a short cache.
func cacheControl(name string) string {
	switch {
	case strings.HasPrefix(name, "assets/"):
		return "public, max-age=31536000, immutable"
	case strings.HasSuffix(name, ".html"):
		return "no-cache"
	default:
		return "public, max-age=3600"
	}
}
