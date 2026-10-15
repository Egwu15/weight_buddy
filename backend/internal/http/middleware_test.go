package httpapi

import (
	"bytes"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestWithRequestTimeoutSetsDeadline(t *testing.T) {
	var hasDeadline bool
	h := withRequestTimeout(50 * time.Millisecond)(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		_, hasDeadline = r.Context().Deadline()
	}))

	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/", nil))

	if !hasDeadline {
		t.Fatal("expected a context deadline to be set")
	}
}

func TestWithRequestTimeoutDisabledWhenNonPositive(t *testing.T) {
	var hasDeadline bool
	h := withRequestTimeout(0)(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		_, hasDeadline = r.Context().Deadline()
	}))

	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/", nil))

	if hasDeadline {
		t.Fatal("expected no context deadline when timeout is disabled")
	}
}

func TestAccessLogRecordsStatus(t *testing.T) {
	var buf bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&buf, nil))

	router := NewRouter(Deps{Logger: logger})
	router.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/healthz", nil))

	out := buf.String()
	if !strings.Contains(out, `"status":200`) {
		t.Fatalf("expected log line to record status 200, got %q", out)
	}
	if !strings.Contains(out, `"path":"/healthz"`) {
		t.Fatalf("expected log line to record the path, got %q", out)
	}
}

func TestAccessLogSkipsWriteHeaderTwice(t *testing.T) {
	rec := &statusRecorder{status: http.StatusOK}
	w := httptest.NewRecorder()

	rec.ResponseWriter = w
	rec.WriteHeader(http.StatusNotFound)
	rec.WriteHeader(http.StatusInternalServerError)

	if rec.status != http.StatusNotFound {
		t.Fatalf("status = %d, want %d", rec.status, http.StatusNotFound)
	}
	if w.Code != http.StatusNotFound {
		t.Fatalf("underlying status = %d, want %d", w.Code, http.StatusNotFound)
	}
}
