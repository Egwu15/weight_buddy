package httpapi

import "net/http"

// handleDeleteMe deletes the authenticated user's account and every row that
// identifies them (usage, entitlement and their RevenueCat event records).
// It answers 204 with no body. A repeat call carrying a still-valid token is
// also 204: the account is simply already gone, which keeps the call
// idempotent for a retry.
//
// The public account-deletion page that Google Play requires lives on the
// embedded site (see internal/site) rather than here; this service only owns
// the DELETE endpoint itself.
func (d Deps) handleDeleteMe(w http.ResponseWriter, r *http.Request) {
	user, ok := userFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized", "Sign in first.")
		return
	}
	if _, err := d.Store.DeleteUser(r.Context(), user.ID); err != nil {
		d.serverError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
