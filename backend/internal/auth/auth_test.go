package auth

import (
	"errors"
	"testing"
	"time"
)

func TestIssueVerifyRoundTrip(t *testing.T) {
	tokens := NewTokens("secret", time.Hour)

	raw, err := tokens.Issue("user-123")
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	got, err := tokens.Verify(raw)
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	if got != "user-123" {
		t.Fatalf("subject = %q, want %q", got, "user-123")
	}
}

func TestVerifyRejectsWrongSecret(t *testing.T) {
	raw, err := NewTokens("secret-a", time.Hour).Issue("user-123")
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	if _, err := NewTokens("secret-b", time.Hour).Verify(raw); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("wrong secret: got %v, want ErrInvalidToken", err)
	}
}

func TestVerifyRejectsExpired(t *testing.T) {
	tokens := NewTokens("secret", time.Hour)
	tokens.now = func() time.Time { return time.Now().Add(-2 * time.Hour) }

	raw, err := tokens.Issue("user-123")
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	tokens.now = time.Now
	if _, err := tokens.Verify(raw); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("expired: got %v, want ErrInvalidToken", err)
	}
}

func TestVerifyRejectsTampered(t *testing.T) {
	tokens := NewTokens("secret", time.Hour)
	raw, err := tokens.Issue("user-123")
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	if _, err := tokens.Verify(raw + "x"); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("tampered: got %v, want ErrInvalidToken", err)
	}
	if _, err := tokens.Verify("not-a-jwt"); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("garbage: got %v, want ErrInvalidToken", err)
	}
}
