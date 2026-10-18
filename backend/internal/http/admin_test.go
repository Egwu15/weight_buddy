package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/tedif/weight-buddy-backend/internal/limits"
)

const testAdminToken = "test-admin-token-123"

func adminDeps(t *testing.T, token string) (Deps, *fakeStore) {
	t.Helper()
	fs := newFakeStore()
	deps := testAuthDeps(fs)
	deps.Limits = &limits.Enforcer{Store: fs, Config: limits.Default(), SpendCap: 25}
	deps.AdminToken = token
	deps.DailySpendCapUSD = 25
	return deps, fs
}

func adminGet(router http.Handler, path string, cookies ...*http.Cookie) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, path, nil)
	for _, c := range cookies {
		req.AddCookie(c)
	}
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	return rec
}

func adminLogin(router http.Handler, user, pass string) *httptest.ResponseRecorder {
	form := url.Values{"user": {user}, "password": {pass}}
	req := httptest.NewRequest(http.MethodPost, "/admin/login",
		strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	return rec
}

func adminPost(router http.Handler, path string, cookies ...*http.Cookie) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, path, nil)
	for _, c := range cookies {
		req.AddCookie(c)
	}
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	return rec
}

func TestAdminDisabledWithoutToken(t *testing.T) {
	deps, _ := adminDeps(t, "")
	router := NewRouter(deps)
	for _, path := range []string{"/admin", "/admin/login"} {
		if rec := adminGet(router, path); rec.Code != http.StatusNotFound {
			t.Fatalf("%s status = %d, want 404 when ADMIN_TOKEN is unset", path, rec.Code)
		}
	}
}

func TestAdminRedirectsToLogin(t *testing.T) {
	deps, _ := adminDeps(t, testAdminToken)
	rec := adminGet(NewRouter(deps), "/admin")
	if rec.Code != http.StatusSeeOther {
		t.Fatalf("status = %d, want 303", rec.Code)
	}
	if got := rec.Header().Get("Location"); got != "/admin/login" {
		t.Fatalf("Location = %q, want /admin/login", got)
	}
	if got := rec.Header().Get("WWW-Authenticate"); got != "" {
		t.Fatalf("unexpected Basic challenge %q (it would prompt before the login page)", got)
	}
}

func TestAdminLoginPageRenders(t *testing.T) {
	deps, _ := adminDeps(t, testAdminToken)
	rec := adminGet(NewRouter(deps), "/admin/login")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	body := rec.Body.String()
	for _, want := range []string{"Sign in", `name="password"`, `action="/admin/login"`} {
		if !strings.Contains(body, want) {
			t.Fatalf("login page missing %q", want)
		}
	}
}

func TestAdminLoginRejectsWrongPassword(t *testing.T) {
	deps, _ := adminDeps(t, testAdminToken)
	rec := adminLogin(NewRouter(deps), "admin", "wrong")
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "Wrong username or password") {
		t.Fatalf("expected a generic error message in the body")
	}
}

func TestAdminLoginRejectsWrongUser(t *testing.T) {
	deps, _ := adminDeps(t, testAdminToken)
	rec := adminLogin(NewRouter(deps), "someone", testAdminToken)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}

func TestAdminLoginSessionAndLogout(t *testing.T) {
	deps, fs := adminDeps(t, testAdminToken)
	router := NewRouter(deps)

	rec := adminLogin(router, "admin", testAdminToken)
	if rec.Code != http.StatusSeeOther {
		t.Fatalf("login status = %d, want 303 (%s)", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Location"); got != "/admin" {
		t.Fatalf("Location = %q, want /admin", got)
	}

	cookies := rec.Result().Cookies()
	if len(cookies) != 1 || cookies[0].Name != adminCookieName {
		t.Fatalf("expected one %s cookie, got %+v", adminCookieName, cookies)
	}
	session := cookies[0]
	if !session.HttpOnly || session.SameSite != http.SameSiteStrictMode || session.Path != "/admin" {
		t.Fatalf("cookie flags = %+v, want HttpOnly + SameSite=Strict + Path=/admin", session)
	}
	if session.Value == "" {
		t.Fatalf("session cookie is empty")
	}

	ctx := context.Background()
	user, _, err := fs.CreateOrGetUser(ctx, "device-admin-0001")
	if err != nil {
		t.Fatalf("seed user: %v", err)
	}
	if err := fs.RecordUsage(ctx, user.ID, "parse", 1, 0.002); err != nil {
		t.Fatalf("seed usage: %v", err)
	}

	// The session alone is enough to read the page.
	page := adminGet(router, "/admin", session)
	if page.Code != http.StatusOK {
		t.Fatalf("admin with session status = %d, want 200 (%s)", page.Code, page.Body.String())
	}
	if !strings.Contains(page.Body.String(), "Usage today") {
		t.Fatalf("admin page did not render the overview")
	}

	// Signing out clears the cookie and sends the browser back to the form.
	out := adminPost(router, "/admin/logout", session)
	if out.Code != http.StatusSeeOther {
		t.Fatalf("logout status = %d, want 303", out.Code)
	}
	if got := out.Header().Get("Location"); got != "/admin/login" {
		t.Fatalf("logout Location = %q, want /admin/login", got)
	}
	cleared := out.Result().Cookies()
	if len(cleared) != 1 || cleared[0].MaxAge >= 0 {
		t.Fatalf("logout should expire the cookie, got %+v", cleared)
	}
}

func TestAdminRejectsTamperedSession(t *testing.T) {
	deps, _ := adminDeps(t, testAdminToken)
	router := NewRouter(deps)
	bad := &http.Cookie{Name: adminCookieName, Value: "9999999999.not-a-signature"}
	if rec := adminGet(router, "/admin", bad); rec.Code != http.StatusSeeOther {
		t.Fatalf("status = %d, want 303 for a tampered cookie", rec.Code)
	}
}

func TestAdminRejectsExpiredSession(t *testing.T) {
	deps, _ := adminDeps(t, testAdminToken)
	expired := &http.Cookie{
		Name:  adminCookieName,
		Value: deps.signAdminSession(time.Now().Add(-time.Hour)),
	}
	if rec := adminGet(NewRouter(deps), "/admin", expired); rec.Code != http.StatusSeeOther {
		t.Fatalf("status = %d, want 303 for an expired session", rec.Code)
	}
}

func TestAdminSessionInvalidAfterTokenRotation(t *testing.T) {
	oldDeps, _ := adminDeps(t, testAdminToken)
	cookie := &http.Cookie{
		Name:  adminCookieName,
		Value: oldDeps.signAdminSession(time.Now().Add(time.Hour)),
	}

	newDeps, _ := adminDeps(t, "a-different-admin-token")
	if rec := adminGet(NewRouter(newDeps), "/admin", cookie); rec.Code != http.StatusSeeOther {
		t.Fatalf("status = %d, want 303 after a token change", rec.Code)
	}
}

func TestAdminAcceptsBasicAuthForScripts(t *testing.T) {
	deps, _ := adminDeps(t, testAdminToken)
	req := httptest.NewRequest(http.MethodGet, "/admin", nil)
	req.SetBasicAuth("admin", testAdminToken)
	rec := httptest.NewRecorder()
	NewRouter(deps).ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
}

func TestAdminRejectsWrongBasicToken(t *testing.T) {
	deps, _ := adminDeps(t, testAdminToken)
	req := httptest.NewRequest(http.MethodGet, "/admin", nil)
	req.SetBasicAuth("admin", "not-the-token")
	rec := httptest.NewRecorder()
	NewRouter(deps).ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
	if got := rec.Header().Get("WWW-Authenticate"); !strings.Contains(got, "Basic") {
		t.Fatalf("WWW-Authenticate = %q, want a Basic challenge", got)
	}
}

func TestAdminRendersReadOnlyStats(t *testing.T) {
	deps, fs := adminDeps(t, testAdminToken)

	ctx := context.Background()
	user, _, err := fs.CreateOrGetUser(ctx, "device-admin-0001")
	if err != nil {
		t.Fatalf("seed user: %v", err)
	}
	sub := "google-sub-admin"
	user.GoogleSub = &sub
	fs.users[user.InstallID] = user
	if err := fs.RecordUsage(ctx, user.ID, "parse", 2, 0.004); err != nil {
		t.Fatalf("seed usage: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/admin", nil)
	req.SetBasicAuth("admin", testAdminToken)
	rec := httptest.NewRecorder()
	NewRouter(deps).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/html") {
		t.Fatalf("Content-Type = %q, want text/html", ct)
	}
	if cc := rec.Header().Get("Cache-Control"); cc != "no-store" {
		t.Fatalf("Cache-Control = %q, want no-store", cc)
	}
	if csp := rec.Header().Get("Content-Security-Policy"); !strings.Contains(csp, "default-src 'none'") {
		t.Fatalf("Content-Security-Policy = %q, want a locked-down policy", csp)
	}

	body := rec.Body.String()
	for _, want := range []string{
		"Weight Buddy",
		"Read-only",
		"Google-linked",
		"Entitlements",
		"Usage today",
		"parse",
		"Aggregates only",
		"Sign out",
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("admin page missing %q", want)
		}
	}
	// The install id must never reach the page.
	if strings.Contains(body, user.InstallID) {
		t.Fatalf("admin page leaked an install id")
	}
}

func TestAdminHeadRequest(t *testing.T) {
	deps, _ := adminDeps(t, testAdminToken)
	req := httptest.NewRequest(http.MethodHead, "/admin", nil)
	req.SetBasicAuth("admin", testAdminToken)
	rec := httptest.NewRecorder()
	NewRouter(deps).ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
}
