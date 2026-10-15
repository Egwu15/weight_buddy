package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"net/http"
)

// requestIDCtxKey keys the request id on the context. It shares the ctxKey type
// declared alongside the user key.
const requestIDCtxKey ctxKey = 1

// RequestIDHeader is the header carrying the request id in and out.
const RequestIDHeader = "X-Request-Id"

// withRequestID gives every request an id, reusing a sane inbound one so a
// client or proxy can correlate logs.
func withRequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get(RequestIDHeader)
		if !validRequestID(id) {
			id = newRequestID()
		}
		w.Header().Set(RequestIDHeader, id)
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), requestIDCtxKey, id)))
	})
}

// requestIDFromContext returns the id placed there by withRequestID.
func requestIDFromContext(ctx context.Context) string {
	id, _ := ctx.Value(requestIDCtxKey).(string)
	return id
}

// validRequestID accepts a modest, header-safe inbound id and rejects anything
// long or containing control characters.
func validRequestID(id string) bool {
	if id == "" || len(id) > 128 {
		return false
	}
	for i := 0; i < len(id); i++ {
		c := id[i]
		if c < 0x20 || c > 0x7e {
			return false
		}
	}
	return true
}

func newRequestID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		// crypto/rand failing is vanishingly rare; an empty id is harmless.
		return ""
	}
	return hex.EncodeToString(b[:])
}
