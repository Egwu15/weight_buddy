package httpapi

import (
	"net/http"
	"strings"
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
// keeps its account. Only a device's first sign-in counts against the
// per-device free-account cap, and the account and the cap are applied in one
// transaction so a rejected or failed signup leaves nothing behind.
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
	ipHash := hashIP(d.JWTSecret, clientIP(r, d.TrustedProxies))
	user, _, allowed, err := d.Store.CreateUserIfAllowed(ctx, installID, ipHash, d.FreeAccountsPerDevice)
	if err != nil {
		d.serverError(w, r, err)
		return
	}
	if !allowed {
		writeError(w, http.StatusTooManyRequests, "device_limit",
			"This device has reached its free account limit. Try again tomorrow.")
		return
	}

	token, err := d.Tokens.Issue(user.ID)
	if err != nil {
		d.serverError(w, r, err)
		return
	}

	writeJSON(w, http.StatusOK, anonymousResponse{Token: token, UserID: user.ID})
}
