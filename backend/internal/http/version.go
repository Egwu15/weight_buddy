package httpapi

import "net/http"

// appVersionResponse is the public force-update contract. The app compares its
// installed version with minimum_version and blocks when it is older. A
// missing or unparsable minimum is treated as "no update required" by the app,
// so a misconfigured or unavailable endpoint can never lock users out.
type appVersionResponse struct {
	MinimumVersion string `json:"minimum_version"`
	StoreURL       string `json:"store_url"`
	Message        string `json:"message"`
}

// handleAppVersion answers the launch-time update check. It is deliberately
// unauthenticated and cheap: the app must be able to ask before it has a
// session, and the answer changes only when the server configuration changes.
func (d Deps) handleAppVersion(w http.ResponseWriter, _ *http.Request) {
	// A stale cached answer could keep a retired build usable (or block one
	// that was just released), so always fetch it fresh.
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, appVersionResponse{
		MinimumVersion: d.AppMinimumVersion,
		StoreURL:       d.AppStoreURL,
		Message:        d.AppUpdateMessage,
	})
}
