package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/tedif/weight-buddy-backend/internal/store"
)

type ctxKey int

const userCtxKey ctxKey = iota

// withUser stores the authenticated account on the request context.
func withUser(ctx context.Context, u store.User) context.Context {
	return context.WithValue(ctx, userCtxKey, u)
}

// userFromContext returns the account placed there by requireAuth.
func userFromContext(ctx context.Context) (store.User, bool) {
	u, ok := ctx.Value(userCtxKey).(store.User)
	return u, ok
}

// requireAuth rejects any request without a valid bearer session token and
// loads the account it names, so downstream handlers can trust the context.
func (d Deps) requireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		token, ok := strings.CutPrefix(header, "Bearer ")
		if !ok || strings.TrimSpace(token) == "" {
			writeError(w, http.StatusUnauthorized, "unauthorized", "Sign in first.")
			return
		}

		userID, err := d.Tokens.Verify(strings.TrimSpace(token))
		if err != nil {
			writeError(w, http.StatusUnauthorized, "unauthorized", "Your session has expired. Sign in again.")
			return
		}

		user, err := d.Store.UserByID(r.Context(), userID)
		if err != nil {
			if errors.Is(err, store.ErrNotFound) {
				writeError(w, http.StatusUnauthorized, "unauthorized", "Your session is no longer valid. Sign in again.")
				return
			}
			writeError(w, http.StatusInternalServerError, "internal", "Something went wrong. Try again.")
			return
		}

		next.ServeHTTP(w, r.WithContext(withUser(r.Context(), user)))
	})
}
