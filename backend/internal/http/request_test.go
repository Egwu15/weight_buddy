package httpapi

import (
	"net/http"
	"net/http/httptest"
	"net/netip"
	"testing"
)

func TestClientIPIgnoresForwardedHeaderFromUntrustedPeer(t *testing.T) {
	trusted := []netip.Prefix{netip.MustParsePrefix("127.0.0.1/32")}

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.RemoteAddr = "203.0.113.9:5555"
	req.Header.Set("X-Forwarded-For", "1.2.3.4")

	if got := clientIP(req, trusted); got != "203.0.113.9" {
		t.Fatalf("clientIP = %q, want the peer 203.0.113.9 (header must be ignored)", got)
	}
}

func TestClientIPTakesRightmostHopFromTrustedPeer(t *testing.T) {
	trusted := []netip.Prefix{netip.MustParsePrefix("127.0.0.1/32")}

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.RemoteAddr = "127.0.0.1:5555"
	// A client prepends "1.2.3.4"; the trusted proxy appends the real peer.
	req.Header.Set("X-Forwarded-For", "1.2.3.4, 198.51.100.7")

	if got := clientIP(req, trusted); got != "198.51.100.7" {
		t.Fatalf("clientIP = %q, want the proxy-appended 198.51.100.7", got)
	}
}

func TestClientIPFallsBackToPeerWithoutHeader(t *testing.T) {
	trusted := []netip.Prefix{netip.MustParsePrefix("127.0.0.1/32")}

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.RemoteAddr = "[::1]:5555"

	if got := clientIP(req, trusted); got != "::1" {
		t.Fatalf("clientIP = %q, want ::1", got)
	}
}
