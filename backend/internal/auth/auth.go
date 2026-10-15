// Package auth issues and verifies app session tokens (anonymous device
// sign-in now, Google sign-in behind the same seam later).
package auth

import (
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// ErrInvalidToken is returned for any token that is malformed, expired, signed
// with the wrong key, or missing a subject. Callers surface it as a 401.
var ErrInvalidToken = errors.New("auth: invalid token")

// issuer identifies tokens this service minted.
const issuer = "weight-buddy"

// Tokens signs and verifies HS256 session tokens. A zero Tokens is not usable;
// build one with NewTokens.
type Tokens struct {
	secret []byte
	ttl    time.Duration
	now    func() time.Time
}

// NewTokens builds a signer with the given secret and token lifetime.
func NewTokens(secret string, ttl time.Duration) *Tokens {
	return &Tokens{secret: []byte(secret), ttl: ttl, now: time.Now}
}

// Issue mints a session token for a user id.
func (t *Tokens) Issue(userID string) (string, error) {
	now := t.now()
	claims := jwt.RegisteredClaims{
		Subject:   userID,
		Issuer:    issuer,
		IssuedAt:  jwt.NewNumericDate(now),
		ExpiresAt: jwt.NewNumericDate(now.Add(t.ttl)),
	}
	signed, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(t.secret)
	if err != nil {
		return "", fmt.Errorf("sign token: %w", err)
	}
	return signed, nil
}

// Verify checks a token's signature and expiry and returns the user id it
// carries. Any problem maps to ErrInvalidToken so callers cannot leak the
// internal reason to clients.
func (t *Tokens) Verify(raw string) (string, error) {
	var claims jwt.RegisteredClaims
	_, err := jwt.ParseWithClaims(raw, &claims, func(tok *jwt.Token) (any, error) {
		return t.secret, nil
	}, jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}), jwt.WithIssuer(issuer), jwt.WithTimeFunc(t.now))
	if err != nil {
		return "", ErrInvalidToken
	}
	if claims.Subject == "" {
		return "", ErrInvalidToken
	}
	return claims.Subject, nil
}
