package httpapi

import (
	"net/http"
	"strings"
)

type googleRequest struct {
	IDToken   string `json:"id_token"`
	InstallID string `json:"install_id"`
}

// googleResponse mirrors the anonymous sign-in response and adds whether the
// Google account was linked onto an existing (anonymous) account.
type googleResponse struct {
	Token  string `json:"token"`
	UserID string `json:"user_id"`
	Linked bool   `json:"linked"`
}

// handleGoogle signs a user in with a Google ID token. The token's subject
// becomes the stable identity. An anonymous session on the request (if any) is
// linked so the same account — and its usage history and RevenueCat purchase —
// is kept; otherwise a new account is created.
func (d Deps) handleGoogle(w http.ResponseWriter, r *http.Request) {
	var req googleRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Expected a JSON body with an id_token and an install_id.")
		return
	}

	idToken := strings.TrimSpace(req.IDToken)
	if idToken == "" {
		writeError(w, http.StatusBadRequest, "invalid_request", "id_token is required.")
		return
	}

	installID := strings.TrimSpace(req.InstallID)
	if len(installID) < minInstallIDLen || len(installID) > maxInstallIDLen {
		writeError(w, http.StatusBadRequest, "invalid_request", "install_id must be between 8 and 128 characters.")
		return
	}

	if d.GoogleVerifier == nil {
		writeError(w, http.StatusServiceUnavailable, "unavailable", "Google sign-in is not configured.")
		return
	}

	sub, err := d.GoogleVerifier.Verify(r.Context(), idToken)
	if err != nil {
		// The token is not logged, on failure or success.
		writeError(w, http.StatusUnauthorized, "unauthorized", "We could not verify your Google sign-in. Try again.")
		return
	}

	// Link only when a valid anonymous session is present and its account has no
	// Google subject yet. When the subject already belongs to a different user,
	// GoogleSignIn returns that user's session instead: we never merge two
	// accounts' usage or entitlements.
	linkUserID := d.anonymousSessionUser(r)

	user, linked, err := d.Store.GoogleSignIn(r.Context(), sub, installID, linkUserID)
	if err != nil {
		d.serverError(w, r, err)
		return
	}

	token, err := d.Tokens.Issue(user.ID)
	if err != nil {
		d.serverError(w, r, err)
		return
	}

	writeJSON(w, http.StatusOK, googleResponse{Token: token, UserID: user.ID, Linked: linked})
}

// anonymousSessionUser returns the id of the account named by a valid bearer
// session, but only when that account has no Google subject yet, so a session
// can never be used to move a subject that is already in use. A missing,
// malformed or expired session is ignored (returns "") rather than failing the
// Google sign-in.
func (d Deps) anonymousSessionUser(r *http.Request) string {
	header := r.Header.Get("Authorization")
	token, ok := strings.CutPrefix(header, "Bearer ")
	if !ok || strings.TrimSpace(token) == "" {
		return ""
	}
	userID, err := d.Tokens.Verify(strings.TrimSpace(token))
	if err != nil {
		return ""
	}
	user, err := d.Store.UserByID(r.Context(), userID)
	if err != nil || user.GoogleSub != nil {
		return ""
	}
	return user.ID
}
