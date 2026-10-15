package httpapi

import (
	"errors"
	"net/http"
	"time"

	"github.com/tedif/weight-buddy-backend/internal/limits"
	"github.com/tedif/weight-buddy-backend/internal/store"
)

type entitlementView struct {
	Entitlement string  `json:"entitlement"`
	Status      string  `json:"status"`
	ExpiresAt   *string `json:"expires_at"`
	IsActive    bool    `json:"is_active"`
}

type meResponse struct {
	UserID            string             `json:"user_id"`
	InstallID         string             `json:"install_id"`
	Tier              string             `json:"tier"`
	Entitlement       *entitlementView   `json:"entitlement"`
	Limits            []limits.KindUsage `json:"limits"`
	SpendRemainingUSD float64            `json:"spend_remaining_usd"`
}

// handleMe returns the signed-in user, their entitlement and their remaining
// allowance for today, so the app can show usage without guessing.
func (d Deps) handleMe(w http.ResponseWriter, r *http.Request) {
	user, ok := userFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized", "Sign in first.")
		return
	}
	ctx := r.Context()

	resp := meResponse{UserID: user.ID, InstallID: user.InstallID, Tier: "free"}

	ent, err := d.Store.Entitlement(ctx, user.ID)
	switch {
	case err == nil:
		active := ent.IsActive(time.Now())
		view := &entitlementView{
			Entitlement: ent.Entitlement,
			Status:      ent.Status,
			IsActive:    active,
		}
		if ent.ExpiresAt != nil {
			formatted := ent.ExpiresAt.UTC().Format(time.RFC3339)
			view.ExpiresAt = &formatted
		}
		resp.Entitlement = view
		if active {
			resp.Tier = "paid"
		}
	case errors.Is(err, store.ErrNotFound):
		// Free tier: no entitlement row yet.
	default:
		d.serverError(w, r, err)
		return
	}

	remaining, err := d.Limits.Remaining(ctx, user.ID, resp.Tier == "paid")
	if err != nil {
		d.serverError(w, r, err)
		return
	}
	resp.Limits = remaining

	spendRemaining, err := d.Limits.SpendRemaining(ctx)
	if err != nil {
		d.serverError(w, r, err)
		return
	}
	resp.SpendRemainingUSD = spendRemaining

	writeJSON(w, http.StatusOK, resp)
}
