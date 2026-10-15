package auth

import (
	"context"
	"errors"
	"fmt"

	"google.golang.org/api/idtoken"
)

// ErrInvalidGoogleToken is returned for any Google ID token that cannot be
// verified: bad signature, expired, wrong audience, or missing subject. Callers
// surface it as a 401. The concrete reason is deliberately not exposed so the
// token and its contents never leak.
var ErrInvalidGoogleToken = errors.New("auth: invalid google id token")

// TokenVerifier verifies a Google ID token and returns its stable subject
// ("sub") claim. It is a small interface so handlers and tests do not depend on
// the concrete Google verifier.
type TokenVerifier interface {
	Verify(ctx context.Context, idToken string) (subject string, err error)
}

// GoogleVerifier verifies Google ID tokens with google.golang.org/api/idtoken
// against a configured audience: our OAuth Web client id. Only the subject
// claim is consumed; the email, name and picture in the token are ignored.
type GoogleVerifier struct {
	audience  string
	validator *idtoken.Validator
}

// NewGoogleVerifier builds a verifier for the given OAuth Web client id.
func NewGoogleVerifier(ctx context.Context, webClientID string) (*GoogleVerifier, error) {
	validator, err := idtoken.NewValidator(ctx)
	if err != nil {
		return nil, fmt.Errorf("init google id token validator: %w", err)
	}
	return &GoogleVerifier{audience: webClientID, validator: validator}, nil
}

// Verify validates the token's signature, expiry and audience and returns its
// subject. Every failure maps to ErrInvalidGoogleToken.
func (g *GoogleVerifier) Verify(ctx context.Context, idToken string) (string, error) {
	payload, err := g.validator.Validate(ctx, idToken, g.audience)
	if err != nil {
		return "", ErrInvalidGoogleToken
	}
	if payload.Subject == "" {
		return "", ErrInvalidGoogleToken
	}
	return payload.Subject, nil
}
