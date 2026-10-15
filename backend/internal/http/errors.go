package httpapi

import "net/http"

// serverError logs the underlying cause and returns the opaque 500 envelope, so
// internal detail never reaches clients but is always recorded server-side.
func (d Deps) serverError(w http.ResponseWriter, r *http.Request, err error) {
	if d.Logger != nil {
		d.Logger.ErrorContext(r.Context(), "request failed", "path", r.URL.Path, "err", err)
	}
	writeError(w, http.StatusInternalServerError, "internal", "Something went wrong. Try again.")
}

// apiError is the single error shape every handler returns:
// {"error":{"code":"...","message":"..."}}.
type apiError struct {
	Error errorBody `json:"error"`
}

type errorBody struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// writeError renders the standard error envelope. Codes are stable, machine
// readable identifiers; messages are safe, human-readable text.
func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, apiError{Error: errorBody{Code: code, Message: message}})
}
