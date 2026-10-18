package httpapi

import (
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"html/template"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/tedif/weight-buddy-backend/internal/store"
)

const (
	adminCookieName = "wb_admin"
	adminSessionTTL = 12 * time.Hour
	adminUser       = "admin"
)

// adminHeaders are applied to every admin response. The page has no scripts and
// no external assets, so the policy can be strict apart from inline styles.
func adminHeaders(w http.ResponseWriter) {
	h := w.Header()
	h.Set("Cache-Control", "no-store")
	h.Set("X-Robots-Tag", "noindex")
	h.Set("X-Content-Type-Options", "nosniff")
	h.Set("X-Frame-Options", "DENY")
	h.Set("Referrer-Policy", "no-referrer")
	h.Set("Content-Security-Policy",
		"default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'")
}

var adminTemplate = template.Must(template.New("admin").Parse(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Weight Buddy admin</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin: 0; background: #241c17; color: #f4e6d1; font: 15px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
  .wrap { max-width: 1000px; margin: 0 auto; padding: 32px 20px 64px; }
  .top { display: flex; align-items: center; justify-content: space-between; gap: 16px; margin-bottom: 4px; }
  h1 { font-size: 1.4rem; margin: 0; }
  .meta { color: #a8988b; margin-bottom: 28px; }
  button { font: inherit; cursor: pointer; border-radius: 8px; padding: 8px 14px; border: 1px solid #4a3a31; background: #2c231f; color: #f4e6d1; }
  button:hover { border-color: #f26a2e; color: #f26a2e; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 12px; }
  .card { border: 1px solid #4a3a31; border-radius: 12px; padding: 14px 16px; background: #2c231f; }
  .label { color: #a8988b; font-size: .72rem; letter-spacing: .08em; text-transform: uppercase; }
  .value { font-size: 1.45rem; margin-top: 4px; font-variant-numeric: tabular-nums; }
  h2 { font-size: .9rem; letter-spacing: .08em; text-transform: uppercase; color: #a8988b; margin: 34px 0 10px; }
  table { width: 100%; border-collapse: collapse; }
  th, td { text-align: left; padding: 9px 10px; border-bottom: 1px solid #3a2e27; }
  th { color: #a8988b; font-size: .72rem; letter-spacing: .06em; text-transform: uppercase; }
  td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; }
  .empty { color: #a8988b; padding: 10px 0; }
  .accent { color: #f26a2e; }
  footer { margin-top: 36px; color: #a8988b; font-size: .78rem; }
</style>
</head>
<body>
<div class="wrap">
  <div class="top">
    <h1>Weight Buddy <span class="accent">admin</span></h1>
    <form method="post" action="/admin/logout"><button type="submit">Sign out</button></form>
  </div>
  <div class="meta">Read-only. Generated {{.GeneratedAt}} UTC. Reload to refresh.</div>

  <div class="grid">
    <div class="card"><div class="label">Users</div><div class="value">{{.Stats.UsersTotal}}</div></div>
    <div class="card"><div class="label">Google-linked</div><div class="value">{{.Stats.UsersGoogleLinked}}</div></div>
    <div class="card"><div class="label">New today</div><div class="value">{{.Stats.UsersCreatedToday}}</div></div>
    <div class="card"><div class="label">New 7 days</div><div class="value">{{.Stats.UsersCreatedLast7}}</div></div>
    <div class="card"><div class="label">Signups today</div><div class="value">{{.Stats.SignupsToday}}</div></div>
    <div class="card"><div class="label">Spend today</div><div class="value">${{printf "%.4f" .Stats.SpendToday}}</div></div>
    <div class="card"><div class="label">Daily cap</div><div class="value">${{printf "%.2f" .SpendCap}}</div></div>
    <div class="card"><div class="label">Cap remaining</div><div class="value">${{printf "%.2f" .SpendRemaining}}</div></div>
    <div class="card"><div class="label">Webhook 24h</div><div class="value">{{.Stats.WebhookEventsToday}}</div></div>
    <div class="card"><div class="label">Webhook total</div><div class="value">{{.Stats.WebhookEventsTotal}}</div></div>
  </div>

  <h2>Entitlements</h2>
  {{if .Stats.Entitlements}}
  <table>
    <thead><tr><th>Entitlement</th><th>Status</th><th class="num">Users</th></tr></thead>
    <tbody>
    {{range .Stats.Entitlements}}<tr><td>{{.Entitlement}}</td><td>{{.Status}}</td><td class="num">{{.Count}}</td></tr>
    {{end}}
    </tbody>
  </table>
  {{else}}<div class="empty">No entitlement rows yet.</div>{{end}}

  <h2>Usage today</h2>
  {{if .Stats.UsageToday}}
  <table>
    <thead><tr><th>Kind</th><th class="num">Calls</th><th class="num">Units</th><th class="num">Cost</th></tr></thead>
    <tbody>
    {{range .Stats.UsageToday}}<tr><td>{{.Kind}}</td><td class="num">{{.Calls}}</td><td class="num">{{printf "%.2f" .Units}}</td><td class="num">${{printf "%.4f" .Cost}}</td></tr>
    {{end}}
    </tbody>
  </table>
  {{else}}<div class="empty">No AI usage today.</div>{{end}}

  <footer>Aggregates only. No tokens, install ids or user text are shown.</footer>
</div>
</body>
</html>
`))

var adminLoginTemplate = template.Must(template.New("admin-login").Parse(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Sign in · Weight Buddy admin</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #241c17; color: #f4e6d1; font: 15px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
  .card { width: min(360px, calc(100vw - 40px)); border: 1px solid #4a3a31; border-radius: 14px; padding: 24px; background: #2c231f; }
  h1 { font-size: 1.15rem; margin: 0 0 4px; }
  .accent { color: #f26a2e; }
  p { color: #a8988b; margin: 0 0 20px; font-size: .85rem; }
  label { display: block; color: #a8988b; font-size: .72rem; letter-spacing: .08em; text-transform: uppercase; margin-bottom: 6px; }
  input { width: 100%; font: inherit; color: #f4e6d1; background: #241c17; border: 1px solid #4a3a31; border-radius: 8px; padding: 10px 12px; margin-bottom: 14px; }
  input:focus { outline: 2px solid #f26a2e; outline-offset: 1px; border-color: #f26a2e; }
  button { width: 100%; font: inherit; cursor: pointer; border-radius: 8px; padding: 11px 14px; border: 0; background: #f26a2e; color: #241c17; font-weight: 700; }
  .error { color: #ff8a65; margin: 0 0 14px; font-size: .85rem; }
</style>
</head>
<body>
<form class="card" method="post" action="/admin/login">
  <h1>Weight Buddy <span class="accent">admin</span></h1>
  <p>Sign in to view the read-only overview.</p>
  {{if .Error}}<p class="error">{{.Error}}</p>{{end}}
  <label for="user">Username</label>
  <input id="user" name="user" value="admin" autocomplete="username" autocapitalize="none" spellcheck="false" required>
  <label for="password">Password</label>
  <input id="password" name="password" type="password" autocomplete="current-password" autofocus required>
  <button type="submit">Sign in</button>
</form>
</body>
</html>
`))

// adminView is the overview template's data. Everything is a number or a short
// label; no user identifiers reach the page.
type adminView struct {
	GeneratedAt    string
	SpendCap       float64
	SpendRemaining float64
	Stats          store.AdminStats
}

// handleAdmin serves the read-only overview. A browser without a session is
// redirected to the login page; a caller that sends explicit (wrong) Basic
// credentials gets a 401 so scripts fail clearly.
func (d Deps) handleAdmin(w http.ResponseWriter, r *http.Request) {
	adminHeaders(w)
	if !d.adminAuthenticated(w, r) {
		return
	}

	stats, err := d.Store.AdminStats(r.Context())
	if err != nil {
		d.serverError(w, r, err)
		return
	}

	// Derive the remainder from the same persisted total the page shows. The
	// enforcer's in-memory counter resets when the process restarts, so mixing
	// the two would display a remainder that disagrees with the spend above.
	remaining := d.DailySpendCapUSD - stats.SpendToday
	if remaining < 0 {
		remaining = 0
	}

	view := adminView{
		GeneratedAt:    time.Now().UTC().Format("2006-01-02 15:04"),
		SpendCap:       d.DailySpendCapUSD,
		SpendRemaining: remaining,
		Stats:          stats,
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := adminTemplate.Execute(w, view); err != nil {
		d.Logger.Error("render admin page", "err", err)
	}
}

func (d Deps) handleAdminLoginPage(w http.ResponseWriter, r *http.Request) {
	adminHeaders(w)
	if d.hasAdminSession(r) || d.validAdminBasic(r) {
		http.Redirect(w, r, "/admin", http.StatusSeeOther)
		return
	}
	d.renderAdminLogin(w, http.StatusOK, "")
}

func (d Deps) handleAdminLogin(w http.ResponseWriter, r *http.Request) {
	adminHeaders(w)
	r.Body = http.MaxBytesReader(w, r.Body, 4096)
	if err := r.ParseForm(); err != nil {
		d.renderAdminLogin(w, http.StatusBadRequest, "Bad request.")
		return
	}

	user := r.PostFormValue("user")
	pass := r.PostFormValue("password")
	if !d.validAdminCredentials(user, pass) {
		d.renderAdminLogin(w, http.StatusUnauthorized, "Wrong username or password.")
		return
	}

	expires := time.Now().Add(adminSessionTTL)
	http.SetCookie(w, &http.Cookie{
		Name:     adminCookieName,
		Value:    d.signAdminSession(expires),
		Path:     "/admin",
		HttpOnly: true,
		Secure:   d.AdminCookieSecure,
		SameSite: http.SameSiteStrictMode,
		Expires:  expires,
		MaxAge:   int(adminSessionTTL.Seconds()),
	})
	http.Redirect(w, r, "/admin", http.StatusSeeOther)
}

func (d Deps) handleAdminLogout(w http.ResponseWriter, r *http.Request) {
	adminHeaders(w)
	http.SetCookie(w, &http.Cookie{
		Name:     adminCookieName,
		Value:    "",
		Path:     "/admin",
		HttpOnly: true,
		Secure:   d.AdminCookieSecure,
		SameSite: http.SameSiteStrictMode,
		MaxAge:   -1,
		Expires:  time.Unix(0, 0),
	})
	http.Redirect(w, r, "/admin/login", http.StatusSeeOther)
}

func (d Deps) renderAdminLogin(w http.ResponseWriter, status int, message string) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(status)
	if err := adminLoginTemplate.Execute(w, struct{ Error string }{Error: message}); err != nil {
		d.Logger.Error("render admin login", "err", err)
	}
}

// adminAuthenticated accepts either a browser session cookie or Basic auth.
// On failure it either redirects to the login page (no credentials at all) or
// answers 401 (credentials were supplied and rejected).
func (d Deps) adminAuthenticated(w http.ResponseWriter, r *http.Request) bool {
	if d.hasAdminSession(r) {
		return true
	}
	if _, _, ok := r.BasicAuth(); ok {
		if d.validAdminBasic(r) {
			return true
		}
		w.Header().Set("WWW-Authenticate", `Basic realm="Weight Buddy admin", charset="UTF-8"`)
		writeError(w, http.StatusUnauthorized, "unauthorized", "Authentication required.")
		return false
	}
	http.Redirect(w, r, "/admin/login", http.StatusSeeOther)
	return false
}

func (d Deps) hasAdminSession(r *http.Request) bool {
	c, err := r.Cookie(adminCookieName)
	return err == nil && d.validAdminSession(c.Value)
}

func (d Deps) validAdminBasic(r *http.Request) bool {
	user, pass, ok := r.BasicAuth()
	return ok && d.validAdminCredentials(user, pass)
}

// validAdminCredentials compares both fields in constant time. The username is
// fixed; the token is the secret.
func (d Deps) validAdminCredentials(user, pass string) bool {
	if d.AdminToken == "" {
		return false
	}
	userOK := subtle.ConstantTimeCompare([]byte(user), []byte(adminUser)) == 1
	passOK := subtle.ConstantTimeCompare([]byte(pass), []byte(d.AdminToken)) == 1
	return userOK && passOK
}

// adminSessionKey derives the cookie-signing key from the admin token, so
// rotating the token invalidates every existing session.
func (d Deps) adminSessionKey() []byte {
	sum := sha256.Sum256([]byte("weight-buddy-admin-session:" + d.AdminToken))
	return sum[:]
}

// signAdminSession returns "<expiryUnix>.<base64url HMAC>".
func (d Deps) signAdminSession(expires time.Time) string {
	payload := strconv.FormatInt(expires.Unix(), 10)
	mac := hmac.New(sha256.New, d.adminSessionKey())
	mac.Write([]byte(payload))
	return payload + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func (d Deps) validAdminSession(raw string) bool {
	if d.AdminToken == "" {
		return false
	}
	payload, encoded, ok := strings.Cut(raw, ".")
	if !ok {
		return false
	}
	mac := hmac.New(sha256.New, d.adminSessionKey())
	mac.Write([]byte(payload))
	want := mac.Sum(nil)
	got, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil || !hmac.Equal(got, want) {
		return false
	}
	unix, err := strconv.ParseInt(payload, 10, 64)
	if err != nil {
		return false
	}
	return time.Now().Before(time.Unix(unix, 0))
}
