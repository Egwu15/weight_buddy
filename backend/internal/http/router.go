// Package httpapi wires the public HTTP surface of the service. The directory
// is named http to match the agreed layout; the package is called httpapi so it
// does not collide with the standard library's net/http.
package httpapi

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5"
)

// Deps are the collaborators the HTTP layer needs. It grows as tasks add
// stores, authenticators and providers.
type Deps struct {
	Logger *slog.Logger
}

// NewRouter builds the application router with all routes registered.
func NewRouter(deps Deps) http.Handler {
	r := chi.NewRouter()
	r.Get("/healthz", handleHealthz)
	return r
}

func handleHealthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// writeJSON writes a JSON response. Handlers use it so every response has a
// consistent shape; error payloads are built on top of it in a later task.
func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}
