package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tedif/weight-buddy-backend/internal/auth"
	"github.com/tedif/weight-buddy-backend/internal/store"
)

// fakeVerifier stands in for Google ID token verification. It maps known tokens
// to subjects and rejects everything else, or fails every call when err is set
// (used to model wrong-audience / malformed tokens at the handler boundary).
type fakeVerifier struct {
	subs map[string]string
	err  error
}

func (f fakeVerifier) Verify(_ context.Context, idToken string) (string, error) {
	if f.err != nil {
		return "", f.err
	}
	if sub, ok := f.subs[idToken]; ok {
		return sub, nil
	}
	return "", auth.ErrInvalidGoogleToken
}

func googleDeps(fs *fakeStore, v auth.TokenVerifier) Deps {
	deps := testAuthDeps(fs)
	deps.GoogleVerifier = v
	return deps
}

func postGoogle(t *testing.T, router http.Handler, body, authHeader string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/v1/auth/google", strings.NewReader(body))
	req.RemoteAddr = "1.2.3.4:5555"
	if authHeader != "" {
		req.Header.Set("Authorization", authHeader)
	}
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	return rec
}

func decodeGoogleResponse(t *testing.T, rec *httptest.ResponseRecorder) googleResponse {
	t.Helper()
	var body googleResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v (%s)", err, rec.Body.String())
	}
	return body
}

// seedAnonymous creates an anonymous account and a matching session token.
func seedAnonymous(t *testing.T, fs *fakeStore, deps Deps, installID string) (store.User, string) {
	t.Helper()
	u, _, err := fs.CreateOrGetUser(t.Context(), installID)
	if err != nil {
		t.Fatalf("seed user: %v", err)
	}
	token, err := deps.Tokens.Issue(u.ID)
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}
	return u, token
}

func TestGoogleSignInNewUser(t *testing.T) {
	fs := newFakeStore()
	deps := googleDeps(fs, fakeVerifier{subs: map[string]string{"good": "sub-new"}})
	router := NewRouter(deps)

	rec := postGoogle(t, router, `{"id_token":"good","install_id":"device-12345678"}`, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}

	body := decodeGoogleResponse(t, rec)
	if body.Linked {
		t.Fatal("a brand-new account must not report linked")
	}
	if body.UserID == "" || body.Token == "" {
		t.Fatalf("empty response: %+v", body)
	}
	gotID, err := deps.Tokens.Verify(body.Token)
	if err != nil || gotID != body.UserID {
		t.Fatalf("token subject %q (err %v) != user_id %q", gotID, err, body.UserID)
	}
	if got := fs.users["device-12345678"].GoogleSub; got == nil || *got != "sub-new" {
		t.Fatalf("created user has google_sub %v, want sub-new", got)
	}
}

func TestGoogleSignInReturningUser(t *testing.T) {
	fs := newFakeStore()
	deps := googleDeps(fs, fakeVerifier{subs: map[string]string{"good": "sub-repeat"}})
	router := NewRouter(deps)

	first := decodeGoogleResponse(t, postGoogle(t, router, `{"id_token":"good","install_id":"device-11111111"}`, ""))
	second := decodeGoogleResponse(t, postGoogle(t, router, `{"id_token":"good","install_id":"device-22222222"}`, ""))

	if first.UserID != second.UserID {
		t.Fatalf("returning subject got different users: %q vs %q", first.UserID, second.UserID)
	}
	if first.Linked || second.Linked {
		t.Fatalf("returning sign-in reported linked: %v / %v", first.Linked, second.Linked)
	}
}

func TestGoogleSignInLinksAnonymousAndKeepsID(t *testing.T) {
	fs := newFakeStore()
	deps := googleDeps(fs, fakeVerifier{subs: map[string]string{"good": "sub-link"}})
	router := NewRouter(deps)

	anonUser, anonToken := seedAnonymous(t, fs, deps, "device-anon-1234")

	rec := postGoogle(t, router, `{"id_token":"good","install_id":"device-anon-1234"}`, "Bearer "+anonToken)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	body := decodeGoogleResponse(t, rec)
	if !body.Linked {
		t.Fatal("linking an anonymous account should report linked")
	}
	if body.UserID != anonUser.ID {
		t.Fatalf("linked user_id = %q, want the anonymous id %q", body.UserID, anonUser.ID)
	}
	if got := fs.users["device-anon-1234"].GoogleSub; got == nil || *got != "sub-link" {
		t.Fatalf("anonymous account was not linked, google_sub = %v", got)
	}
}

func TestGoogleSignInDoesNotMergeAcrossUsers(t *testing.T) {
	fs := newFakeStore()
	deps := googleDeps(fs, fakeVerifier{subs: map[string]string{
		"owner": "sub-owned",
		"other": "sub-other",
	}})
	router := NewRouter(deps)

	// The subject already belongs to this first user.
	owner := decodeGoogleResponse(t, postGoogle(t, router, `{"id_token":"owner","install_id":"device-owner-11"}`, ""))

	// A different anonymous account signs in with the same subject.
	anonUser, anonToken := seedAnonymous(t, fs, deps, "device-other-22")
	rec := postGoogle(t, router, `{"id_token":"owner","install_id":"device-other-22"}`, "Bearer "+anonToken)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	body := decodeGoogleResponse(t, rec)

	if body.UserID != owner.UserID {
		t.Fatalf("user_id = %q, want the subject owner %q", body.UserID, owner.UserID)
	}
	if body.Linked {
		t.Fatal("a subject already owned by another user must not report linked")
	}
	// The anonymous account must be untouched: no subject, no merge.
	if got := fs.users["device-other-22"].GoogleSub; got != nil {
		t.Fatalf("anonymous account was modified, google_sub = %v", got)
	}
	if fs.users["device-other-22"].ID != anonUser.ID {
		t.Fatal("anonymous account id changed")
	}
}

func TestGoogleSignInRejectsBadRequests(t *testing.T) {
	fs := newFakeStore()
	router := NewRouter(googleDeps(fs, fakeVerifier{subs: map[string]string{"good": "sub-x"}}))

	tests := []struct {
		name string
		body string
	}{
		{"not json", `not json`},
		{"missing id token", `{"install_id":"device-12345678"}`},
		{"missing install id", `{"id_token":"good"}`},
		{"install id too short", `{"id_token":"good","install_id":"short"}`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := postGoogle(t, router, tt.body, "")
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400 (%s)", rec.Code, rec.Body.String())
			}
			if code := errorCode(t, rec); code != "invalid_request" {
				t.Fatalf("code = %q, want invalid_request", code)
			}
		})
	}
}

func TestGoogleSignInRejectsInvalidToken(t *testing.T) {
	fs := newFakeStore()

	t.Run("unknown token", func(t *testing.T) {
		router := NewRouter(googleDeps(fs, fakeVerifier{subs: map[string]string{"good": "sub-x"}}))
		rec := postGoogle(t, router, `{"id_token":"bad","install_id":"device-12345678"}`, "")
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("status = %d, want 401 (%s)", rec.Code, rec.Body.String())
		}
		if code := errorCode(t, rec); code != "unauthorized" {
			t.Fatalf("code = %q, want unauthorized", code)
		}
	})

	t.Run("verifier failure (wrong audience / malformed)", func(t *testing.T) {
		router := NewRouter(googleDeps(fs, fakeVerifier{err: auth.ErrInvalidGoogleToken}))
		rec := postGoogle(t, router, `{"id_token":"whatever","install_id":"device-12345678"}`, "")
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("status = %d, want 401 (%s)", rec.Code, rec.Body.String())
		}
	})
}

func TestGoogleSignInRejectsAccountSwitch(t *testing.T) {
	fs := newFakeStore()
	deps := googleDeps(fs, fakeVerifier{subs: map[string]string{
		"account-a": "sub-a",
		"account-b": "sub-b",
	}})
	router := NewRouter(deps)

	// The device's install id becomes linked to Google account A.
	first := postGoogle(t, router, `{"id_token":"account-a","install_id":"device-switch-01"}`, "")
	if first.Code != http.StatusOK {
		t.Fatalf("first sign-in = %d, want 200 (%s)", first.Code, first.Body.String())
	}
	token := decodeGoogleResponse(t, first).Token

	// Signing in with account B on the same install id must be a clear 409,
	// not a 500.
	second := postGoogle(t, router, `{"id_token":"account-b","install_id":"device-switch-01"}`, "Bearer "+token)
	if second.Code != http.StatusConflict {
		t.Fatalf("account switch = %d, want 409 (%s)", second.Code, second.Body.String())
	}
	if code := errorCode(t, second); code != "account_conflict" {
		t.Fatalf("code = %q, want account_conflict", code)
	}
}

func TestGoogleSignInIgnoresInvalidAnonymousSession(t *testing.T) {
	fs := newFakeStore()
	deps := googleDeps(fs, fakeVerifier{subs: map[string]string{"good": "sub-z"}})
	router := NewRouter(deps)

	// A garbage session must not fail the sign-in; a new account is created.
	rec := postGoogle(t, router, `{"id_token":"good","install_id":"device-99999999"}`, "Bearer not-a-real-token")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	body := decodeGoogleResponse(t, rec)
	if body.Linked {
		t.Fatal("invalid session must not link")
	}
}
