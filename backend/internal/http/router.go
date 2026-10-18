// Package httpapi wires the public HTTP surface of the service. The directory
// is named http to match the agreed layout; the package is called httpapi so it
// does not collide with the standard library's net/http.
package httpapi

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"net/netip"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/tedif/weight-buddy-backend/internal/ai"
	"github.com/tedif/weight-buddy-backend/internal/auth"
	"github.com/tedif/weight-buddy-backend/internal/limits"
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
	// GoogleVerifier verifies Google ID tokens. Nil disables the Google
	// sign-in route with a 503.
	GoogleVerifier auth.TokenVerifier
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

	// Site serves the public pages (home, privacy, terms, account deletion)
	// from the embedded build. It is the fallback for any path no API route
	// claimed, so API routes always win. Nil answers those paths with a JSON
	// 404, which keeps API-only tests simple.
	Site http.Handler

	// Limits enforces daily quotas and the global spend cap. Required by the
	// metered routes.
	Limits *limits.Enforcer

	// Provider is the AI vendor seam. Nil disables the metered AI routes with
	// a 503.
	Provider ai.Provider

	// RateLimitPerIPPerMinute and RateLimitPerUserPerMinute bound request
	// rates. Zero disables the corresponding limiter.
	RateLimitPerIPPerMinute   int
	RateLimitPerUserPerMinute int

	// TrustedProxies are the networks whose X-Forwarded-For headers the
	// client-IP resolution may trust (Caddy on loopback by default).
	TrustedProxies []netip.Prefix

	// AdminToken enables the read-only /admin page when non-empty. Empty
	// leaves the route unregistered.
	AdminToken string
	// AdminCookieSecure marks the admin session cookie Secure. Set in
	// production (TLS); leave false for local HTTP.
	AdminCookieSecure bool
	// DailySpendCapUSD is shown on the admin page; enforcement stays in Limits.
	DailySpendCapUSD float64

	// AppMinimumVersion, AppStoreURL and AppUpdateMessage back the public
	// /v1/app/version check. Empty values keep the route answering with an
	// empty minimum, which the app treats as "no update required".
	AppMinimumVersion string
	AppStoreURL       string
	AppUpdateMessage  string
}

// NewRouter builds the application router with all routes registered.
func NewRouter(deps Deps) http.Handler {
	r := chi.NewRouter()
	r.Use(withRequestID)
	r.Use(accessLog(deps.Logger))
	r.Use(withRequestTimeout(deps.RequestTimeout))

	// Per-IP limiting runs before any auth so anonymous traffic is bounded too.
	if deps.RateLimitPerIPPerMinute > 0 {
		r.Use(deps.rateLimitByIP(newRateLimiter(deps.RateLimitPerIPPerMinute, time.Minute)))
	}

	r.Get("/healthz", handleHealthz)

	r.Route("/v1", func(r chi.Router) {
		// An unknown /v1 path is an API error, not the public site's HTML 404.
		r.NotFound(notFoundJSON)
		r.Post("/auth/anonymous", deps.handleAnonymous)
		r.Post("/auth/google", deps.handleGoogle)
		r.Post("/webhooks/revenuecat", deps.handleRevenueCatWebhook)

		// The app checks this before sign-in, so it must stay public.
		r.Get("/app/version", deps.handleAppVersion)

		// Deletion verifies the session token but tolerates an already-deleted
		// account, so a repeated call is a no-op 204 rather than a 401.
		r.Group(func(r chi.Router) {
			r.Use(deps.requireToken)
			if deps.RateLimitPerUserPerMinute > 0 {
				r.Use(deps.rateLimitByUser(newRateLimiter(deps.RateLimitPerUserPerMinute, time.Minute)))
			}
			r.Delete("/me", deps.handleDeleteMe)
		})

		r.Group(func(r chi.Router) {
			r.Use(deps.requireAuth)
			if deps.RateLimitPerUserPerMinute > 0 {
				r.Use(deps.rateLimitByUser(newRateLimiter(deps.RateLimitPerUserPerMinute, time.Minute)))
			}
			r.Get("/me", deps.handleMe)

			r.Post("/ai/transcribe", deps.handleTranscribe)
			r.Post("/ai/parse", deps.handleParseAuto)
			r.Post("/ai/parse-meal", deps.handleParseMeal)
			r.Post("/ai/parse-exercise", deps.handleParseExercise)
			r.Post("/ai/chat", deps.handleChat)
			r.Post("/ai/distill-memories", deps.handleDistillMemories)
			r.Post("/ai/extract-exercises", deps.handleExtractExercises)
		})
	})

	// The operator page is registered only when a token is configured, so a
	// deployment without ADMIN_TOKEN has no /admin route at all.
	if deps.AdminToken != "" {
		r.Get("/admin", deps.handleAdmin)
		r.Head("/admin", deps.handleAdmin)
		r.Get("/admin/login", deps.handleAdminLoginPage)
		r.Post("/admin/login", deps.handleAdminLogin)
		r.Post("/admin/logout", deps.handleAdminLogout)
	}

	// Everything that is not an API route falls through to the public site.
	// Serving it from NotFound (rather than a catch-all route) is what keeps
	// the API authoritative: chi only reaches here after no route matched.
	r.NotFound(func(w http.ResponseWriter, r *http.Request) {
		if deps.Site == nil {
			notFoundJSON(w, r)
			return
		}
		deps.Site.ServeHTTP(w, r)
	})

	return r
}

func handleHealthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// notFoundJSON is the API's 404: unknown /v1 paths and, when no site is wired,
// every other unknown path.
func notFoundJSON(w http.ResponseWriter, _ *http.Request) {
	writeError(w, http.StatusNotFound, "not_found", "Not found.")
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
