package httpapi

import (
	"html/template"
	"net/http"
)

// handleDeleteMe deletes the authenticated user's account and every row that
// identifies them (usage, entitlement and their RevenueCat event records).
// It answers 204 with no body. A repeat call carrying a still-valid token is
// also 204: the account is simply already gone, which keeps the call
// idempotent for a retry.
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

// deleteAccountPage is the public page Play requires next to in-app deletion:
// it explains the in-app path and an email fallback for people without the app.
var deleteAccountPage = template.Must(template.New("delete-account").Parse(`
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Delete your Weight Buddy account</title>
<style>
  :root { color-scheme: light dark; }
  body { margin: 0; font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
         background: #221a17; color: #f4ead9; }
  main { max-width: 40rem; margin: 0 auto; padding: 3rem 1.25rem 4rem; }
  h1 { font-size: 1.6rem; margin: 0 0 .25rem; }
  h2 { font-size: 1.1rem; margin: 2rem 0 .5rem; }
  p, li { color: #d9cdb8; }
  a { color: #f2b53c; }
  .muted { color: #a8937f; font-size: .9rem; }
</style>
</head>
<body>
<main>
  <h1>Delete your Weight Buddy account</h1>
  <p class="muted">Weight Buddy is the calorie and workout tracker app.</p>

  <h2>Delete it in the app</h2>
  <p>
    Open the app, go to <strong>Settings &rarr; Account &amp; voice</strong>, and
    tap <strong>Delete account</strong>. You can also choose to erase the meal
    and workout data stored on that device. Deletion takes effect immediately.
  </p>

  <h2>Don't have the app installed?</h2>
  <p>
    Email <a href="mailto:{{.SupportEmail}}">{{.SupportEmail}}</a> from the
    address you used, or include the account's user id, and ask us to delete
    your account. We will remove it and confirm by reply.
  </p>

  <h2>What gets deleted</h2>
  <p>
    Your account record, its subscription entitlement and its usage history are
    deleted. Saved meals, workouts and weigh-ins live only on your device and
    are removed separately if you choose to erase them in the app.
  </p>
</main>
</body>
</html>
`))

// deleteAccountView is the data the page needs. The support address is
// HTML-escaped by the template engine.
type deleteAccountView struct {
	SupportEmail string
}

// handleDeleteAccount renders the public account-deletion page.
func (d Deps) handleDeleteAccount(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	view := deleteAccountView{SupportEmail: d.SupportEmail}
	if view.SupportEmail == "" {
		view.SupportEmail = "support@example.com"
	}
	if err := deleteAccountPage.Execute(w, view); err != nil {
		// The status line is already flushed; this can only be logged.
		if d.Logger != nil {
			d.Logger.Error("render delete-account page", "err", err)
		}
	}
}
