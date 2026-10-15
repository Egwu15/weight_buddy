package httpapi

import (
	"net/http"
	"strconv"
	"sync"
	"time"
)

// maxTrackedKeys bounds the rate-limiter map; beyond it we sweep expired
// buckets so memory cannot grow without limit under a key-spraying client.
const maxTrackedKeys = 10000

// rateLimiter is a fixed-window counter per key. It is intentionally simple:
// the goal is to blunt abuse, not to shape traffic precisely.
type rateLimiter struct {
	mu      sync.Mutex
	limit   int
	window  time.Duration
	now     func() time.Time
	buckets map[string]*bucket
}

type bucket struct {
	count int
	reset time.Time
}

func newRateLimiter(limit int, window time.Duration) *rateLimiter {
	return &rateLimiter{
		limit:   limit,
		window:  window,
		now:     time.Now,
		buckets: make(map[string]*bucket),
	}
}

// allow records one hit and reports whether the key is within its limit. It
// also returns how long until the window resets, for a Retry-After header.
func (l *rateLimiter) allow(key string) (bool, time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := l.now()
	if len(l.buckets) > maxTrackedKeys {
		l.sweep(now)
	}

	b, ok := l.buckets[key]
	if !ok || !now.Before(b.reset) {
		b = &bucket{reset: now.Add(l.window)}
		l.buckets[key] = b
	}
	b.count++
	if b.count > l.limit {
		return false, b.reset.Sub(now)
	}
	return true, 0
}

// sweep drops buckets whose window has already reset. Callers hold the lock.
func (l *rateLimiter) sweep(now time.Time) {
	for k, b := range l.buckets {
		if !now.Before(b.reset) {
			delete(l.buckets, k)
		}
	}
}

// rateLimitByIP limits requests per client address.
func (d Deps) rateLimitByIP(limiter *rateLimiter) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if allowed, retryAfter := limiter.allow(clientIP(r)); !allowed {
				d.rateLimited(w, retryAfter)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// rateLimitByUser limits requests per authenticated user. It must run after
// requireAuth so the user is on the context.
func (d Deps) rateLimitByUser(limiter *rateLimiter) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			user, ok := userFromContext(r.Context())
			if !ok {
				next.ServeHTTP(w, r)
				return
			}
			if allowed, retryAfter := limiter.allow(user.ID); !allowed {
				d.rateLimited(w, retryAfter)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func (d Deps) rateLimited(w http.ResponseWriter, retryAfter time.Duration) {
	seconds := int(retryAfter.Seconds())
	if seconds < 1 {
		seconds = 1
	}
	w.Header().Set("Retry-After", strconv.Itoa(seconds))
	writeError(w, http.StatusTooManyRequests, "rate_limited",
		"Too many requests. Slow down and try again shortly.")
}
