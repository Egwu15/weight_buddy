package httpapi

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/tedif/weight-buddy-backend/internal/limits"
	"github.com/tedif/weight-buddy-backend/internal/store"
)

// paidTier reports whether the user currently has an active entitlement.
func (d Deps) paidTier(ctx context.Context, userID string) (bool, error) {
	ent, err := d.Store.Entitlement(ctx, userID)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			return false, nil
		}
		return false, err
	}
	return ent.IsActive(time.Now()), nil
}

// gate runs the auth, entitlement and limit checks every metered endpoint
// needs. It writes the appropriate error and returns ok=false when the request
// must not proceed; otherwise it returns the user and the estimated cost of the
// call the handler is about to make.
func (d Deps) gate(w http.ResponseWriter, r *http.Request, kind limits.Kind) (store.User, float64, bool) {
	user, ok := userFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized", "Sign in first.")
		return store.User{}, 0, false
	}
	if d.Provider == nil {
		writeError(w, http.StatusServiceUnavailable, "not_configured", "The assistant is not available right now.")
		return store.User{}, 0, false
	}

	paid, err := d.paidTier(r.Context(), user.ID)
	if err != nil {
		d.serverError(w, r, err)
		return store.User{}, 0, false
	}

	decision, err := d.Limits.Check(r.Context(), user.ID, paid, kind)
	if err != nil {
		d.serverError(w, r, err)
		return store.User{}, 0, false
	}
	switch decision.Reason {
	case limits.ReasonUserCap:
		writeError(w, http.StatusTooManyRequests, "limit_reached",
			"You have used today's allowance for this feature. It resets tomorrow.")
		return store.User{}, 0, false
	case limits.ReasonSpendCap:
		writeError(w, http.StatusServiceUnavailable, "spend_cap",
			"The assistant is at capacity right now. Try again later.")
		return store.User{}, 0, false
	}

	return user, decision.Cost, true
}

// recordUsage logs a completed, successful call. It is best-effort: a metering
// write failure must never turn a good answer into an error for the user.
func (d Deps) recordUsage(ctx context.Context, user store.User, kind limits.Kind, cost float64) {
	if err := d.Limits.RecordUsage(ctx, user.ID, kind, cost); err != nil && d.Logger != nil {
		d.Logger.ErrorContext(ctx, "record usage", "err", err, "kind", string(kind))
	}
}
