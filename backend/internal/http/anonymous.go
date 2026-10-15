package httpapi

import (
	"errors"
	"net/http"
	"strings"

	"github.com/tedif/weight-buddy-backend/internal/store"
)

const (
	minInstallIDLen = 8
	maxInstallIDLen = 128
)

type anonymousRequest struct {
	InstallID string `json:"install_id"`
}

type anonymousResponse struct {
	Token  string `json:"token"`
	UserID string `json:"user_id"`
}

// handleAnonymous signs a device in. The client sends a random install id and
// gets back a user id and a session token; a device that has signed in before
// keeps its account. Only the first sight of a device counts against the
// per-device free-account cap.
func (d Deps) handleAnonymous(w http.ResponseWriter, r *http.Request) {
	var req anonymousRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Expected a JSON body with an install_id.")
		return
	}

	installID := strings.TrimSpace(req.InstallID)
	if len(installID) < minInstallIDLen || len(installID) > maxInstallIDLen {
		writeError(w, http.StatusBadRequest, "invalid_request", "install_id must be between 8 and 128 characters.")
		return
	}

	ctx := r.Context()
	user, err := d.Store.UserByInstallID(ctx, installID)
	switch {
	case err == nil:
		// Known device: sign in without touching the creation cap.
	case errors.Is(err, store.ErrNotFound):
		allowed, capErr := d.Store.RegisterSignup(ctx, hashIP(d.JWTSecret, clientIP(r)), d.FreeAccountsPerDevice)
		if capErr != nil {
			d.serverError(w, r, capErr)
			return
		}
		if !allowed {
			writeError(w, http.StatusTooManyRequests, "device_limit",
				"This device has reached its free account limit. Try again tomorrow.")
			return
		}
		user, _, err = d.Store.CreateOrGetUser(ctx, installID)
		if err != nil {
			d.serverError(w, r, err)
			return
		}
	default:
		d.serverError(w, r, err)
		return
	}

	token, err := d.Tokens.Issue(user.ID)
	if err != nil {
		d.serverError(w, r, err)
		return
	}

	writeJSON(w, http.StatusOK, anonymousResponse{Token: token, UserID: user.ID})
}
