package httpapi

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestWithRequestIDGeneratesAnID(t *testing.T) {
	var seen string
	h := withRequestID(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		seen = requestIDFromContext(r.Context())
	}))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))

	if seen == "" {
		t.Fatal("expected a generated request id on the context")
	}
	if rec.Header().Get(RequestIDHeader) != seen {
		t.Fatalf("response header %q != context id %q", rec.Header().Get(RequestIDHeader), seen)
	}
}

func TestWithRequestIDReusesInboundID(t *testing.T) {
	var seen string
	h := withRequestID(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		seen = requestIDFromContext(r.Context())
	}))

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set(RequestIDHeader, "abc-123")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if seen != "abc-123" {
		t.Fatalf("context id = %q, want abc-123", seen)
	}
}

func TestWithRequestIDReplacesInvalid(t *testing.T) {
	var seen string
	h := withRequestID(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		seen = requestIDFromContext(r.Context())
	}))

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set(RequestIDHeader, "bad\nvalue")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if seen == "bad\nvalue" || seen == "" {
		t.Fatalf("expected a fresh request id, got %q", seen)
	}
}
