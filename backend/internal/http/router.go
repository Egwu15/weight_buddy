// Package httpapi wires the public HTTP surface of the service. The directory
// is named http to match the agreed layout; the package is called httpapi so it
// does not collide with the standard library's net/http.
package httpapi

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/tedif/weight-buddy-backend/internal/auth"
)

// Deps are the collaborators the HTTP layer needs. It grows as tasks add
// stores, authenticators and providers.
type Deps struct {
	Logger *slog.Logger
	// RequestTimeout bounds each request. Zero disables the deadline, which is
	// convenient in tests; production always sets it from config.
	RequestTimeout time.Duration

	// Store is the persistence layer. Required by every non-health route.
	Store Store
	// Tokens issues and verifies app session tokens.
	Tokens *auth.Tokens
	// JWTSecret salts the hashed client IP used for the per-device cap.
	JWTSecret string
	// FreeAccountsPerDevice caps anonymous free accounts per device per day.
	FreeAccountsPerDevice int

	// RevenueCatWebhookSecret authenticates webhook deliveries; empty disables
	// the webhook route with a 503.
	RevenueCatWebhookSecret string
	// RevenueCatEntitlementID is the entitlement a purchase grants when the
	// payload does not name one.
	RevenueCatEntitlementID string
}

// NewRouter builds the application router with all routes registered.
func NewRouter(deps Deps) http.Handler {
	r := chi.NewRouter()
	r.Use(accessLog(deps.Logger))
	r.Use(withRequestTimeout(deps.RequestTimeout))
	r.Get("/healthz", handleHealthz)

	r.Route("/v1", func(r chi.Router) {
		r.Post("/auth/anonymous", deps.handleAnonymous)
		r.Post("/webhooks/revenuecat", deps.handleRevenueCatWebhook)
	})

	return r
}

func handleHealthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// writeJSON writes a JSON response. Handlers use it so every response has a
// consistent shape; error payloads are built on top of it in a later task.
func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	// The status line is already flushed, so an encode failure can only be
	// logged, not turned into an error response. Payloads here are small,
	// fixed-shape structs, so this is effectively unreachable.
	_ = json.NewEncoder(w).Encode(payload)
}
