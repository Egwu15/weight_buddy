package httpapi

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestRateLimiterAllowsUpToLimitThenBlocks(t *testing.T) {
	l := newRateLimiter(2, time.Minute)
	now := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	l.now = func() time.Time { return now }

	for i := 1; i <= 2; i++ {
		if allowed, _ := l.allow("k"); !allowed {
			t.Fatalf("hit %d should be allowed", i)
		}
	}
	allowed, retryAfter := l.allow("k")
	if allowed {
		t.Fatal("third hit should be blocked")
	}
	if retryAfter <= 0 {
		t.Fatalf("retryAfter = %v, want positive", retryAfter)
	}

	// A different key has its own budget.
	if allowed, _ := l.allow("other"); !allowed {
		t.Fatal("a different key should be allowed")
	}
}

func TestRateLimiterResetsAfterWindow(t *testing.T) {
	l := newRateLimiter(1, time.Minute)
	now := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	l.now = func() time.Time { return now }

	if allowed, _ := l.allow("k"); !allowed {
		t.Fatal("first hit should be allowed")
	}
	if allowed, _ := l.allow("k"); allowed {
		t.Fatal("second hit in the same window should be blocked")
	}

	now = now.Add(2 * time.Minute)
	if allowed, _ := l.allow("k"); !allowed {
		t.Fatal("hit in a new window should be allowed")
	}
}

func TestRouterRateLimitsPerIP(t *testing.T) {
	deps := testAuthDeps(newFakeStore())
	deps.RateLimitPerIPPerMinute = 1
	router := NewRouter(deps)

	first := httptest.NewRecorder()
	router.ServeHTTP(first, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if first.Code != http.StatusOK {
		t.Fatalf("first status = %d, want 200", first.Code)
	}

	second := httptest.NewRecorder()
	router.ServeHTTP(second, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if second.Code != http.StatusTooManyRequests {
		t.Fatalf("second status = %d, want 429", second.Code)
	}
	if code := errorCode(t, second); code != "rate_limited" {
		t.Fatalf("code = %q, want rate_limited", code)
	}
	if second.Header().Get("Retry-After") == "" {
		t.Fatal("expected a Retry-After header")
	}
}

func TestRouterRateLimitsPerUser(t *testing.T) {
	fs := newFakeStore()
	deps, token := meDeps(t, fs)
	deps.RateLimitPerUserPerMinute = 1
	router := NewRouter(deps)

	first := getMe(t, router, token)
	if first.Code != http.StatusOK {
		t.Fatalf("first status = %d, want 200 (%s)", first.Code, first.Body.String())
	}
	second := getMe(t, router, token)
	if second.Code != http.StatusTooManyRequests {
		t.Fatalf("second status = %d, want 429", second.Code)
	}
}
