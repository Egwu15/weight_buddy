package auth

import (
	"bytes"
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"math/big"
	"net/http"
	"testing"
	"time"

	"google.golang.org/api/idtoken"
	"google.golang.org/api/option"
)

const testKeyID = "test-key"

// TestGoogleVerifier exercises the real verifier against a locally signed token
// and a fake JWKS. This is where audience enforcement is actually proven: the
// handler tests use a fake verifier and only check the 401 path.
func TestGoogleVerifier(t *testing.T) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	otherKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}

	now := time.Now()
	future := now.Add(time.Hour).Unix()
	past := now.Add(-time.Hour).Unix()

	tests := []struct {
		name     string
		signing  *rsa.PrivateKey
		claims   map[string]any
		audience string
		wantSub  string
		wantErr  bool
	}{
		{
			name:     "valid token",
			signing:  key,
			audience: "web-client.apps.googleusercontent.com",
			claims: map[string]any{
				"iss": "https://accounts.google.com",
				"aud": "web-client.apps.googleusercontent.com",
				"sub": "sub-123",
				"exp": future,
				"iat": now.Unix(),
			},
			wantSub: "sub-123",
		},
		{
			name:     "wrong audience",
			signing:  key,
			audience: "web-client.apps.googleusercontent.com",
			claims: map[string]any{
				"iss": "https://accounts.google.com",
				"aud": "someone-elses-client.apps.googleusercontent.com",
				"sub": "sub-123",
				"exp": future,
				"iat": now.Unix(),
			},
			wantErr: true,
		},
		{
			name:     "expired token",
			signing:  key,
			audience: "web-client.apps.googleusercontent.com",
			claims: map[string]any{
				"iss": "https://accounts.google.com",
				"aud": "web-client.apps.googleusercontent.com",
				"sub": "sub-123",
				"exp": past,
				"iat": past,
			},
			wantErr: true,
		},
		{
			name:     "missing subject claim",
			signing:  key,
			audience: "web-client.apps.googleusercontent.com",
			claims: map[string]any{
				"iss": "https://accounts.google.com",
				"aud": "web-client.apps.googleusercontent.com",
				"exp": future,
				"iat": now.Unix(),
			},
			wantErr: true,
		},
		{
			name:     "signature from a different key",
			signing:  otherKey,
			audience: "web-client.apps.googleusercontent.com",
			claims: map[string]any{
				"iss": "https://accounts.google.com",
				"aud": "web-client.apps.googleusercontent.com",
				"sub": "sub-123",
				"exp": future,
				"iat": now.Unix(),
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			token := signRS256(t, tt.signing, testKeyID, tt.claims)
			validator, err := idtoken.NewValidator(context.Background(),
				option.WithHTTPClient(jwksClient(t, &key.PublicKey, testKeyID)))
			if err != nil {
				t.Fatalf("new validator: %v", err)
			}
			verifier := &GoogleVerifier{audience: tt.audience, validator: validator}

			sub, err := verifier.Verify(context.Background(), token)
			if tt.wantErr {
				if !errors.Is(err, ErrInvalidGoogleToken) {
					t.Fatalf("err = %v, want ErrInvalidGoogleToken", err)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if sub != tt.wantSub {
				t.Fatalf("subject = %q, want %q", sub, tt.wantSub)
			}
		})
	}
}

func signRS256(t *testing.T, key *rsa.PrivateKey, kid string, claims map[string]any) string {
	t.Helper()
	header, err := json.Marshal(map[string]any{"alg": "RS256", "typ": "JWT", "kid": kid})
	if err != nil {
		t.Fatalf("marshal header: %v", err)
	}
	payload, err := json.Marshal(claims)
	if err != nil {
		t.Fatalf("marshal payload: %v", err)
	}
	signingInput := base64.RawURLEncoding.EncodeToString(header) + "." + base64.RawURLEncoding.EncodeToString(payload)
	digest := sha256.Sum256([]byte(signingInput))
	sig, err := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, digest[:])
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	return signingInput + "." + base64.RawURLEncoding.EncodeToString(sig)
}

// jwksClient answers the Google certs request with a JWKS holding one RSA key,
// so the verifier can be exercised without touching the network.
func jwksClient(t *testing.T, pub *rsa.PublicKey, kid string) *http.Client {
	t.Helper()
	body, err := json.Marshal(map[string]any{
		"keys": []map[string]any{{
			"kid": kid,
			"alg": "RS256",
			"kty": "RSA",
			"use": "sig",
			"n":   base64.RawURLEncoding.EncodeToString(pub.N.Bytes()),
			"e":   base64.RawURLEncoding.EncodeToString(big.NewInt(int64(pub.E)).Bytes()),
		}},
	})
	if err != nil {
		t.Fatalf("marshal jwks: %v", err)
	}
	return &http.Client{Transport: roundTripFunc(func(*http.Request) (*http.Response, error) {
		return &http.Response{
			StatusCode: http.StatusOK,
			Body:       io.NopCloser(bytes.NewReader(body)),
			Header:     make(http.Header),
		}, nil
	})}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(req *http.Request) (*http.Response, error) { return f(req) }
