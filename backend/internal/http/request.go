package httpapi

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"net/netip"
	"strings"
)

// maxJSONBody caps request JSON so a client cannot exhaust memory with a huge
// body. Audio uploads use their own, larger limit.
const maxJSONBody = 1 << 20 // 1 MiB

var errBadJSON = errors.New("invalid JSON body")

// decodeJSON reads a small JSON request body into dst, enforcing the body cap.
func decodeJSON(w http.ResponseWriter, r *http.Request, dst any) error {
	r.Body = http.MaxBytesReader(w, r.Body, maxJSONBody)
	if err := json.NewDecoder(r.Body).Decode(dst); err != nil {
		return errBadJSON
	}
	return nil
}

// clientIP resolves the caller's address. It trusts the forwarded headers only
// when the immediate peer is a configured trusted proxy (Caddy on localhost by
// default); otherwise it uses the peer address. That stops a client from
// spoofing X-Forwarded-For to dodge per-IP limits or the per-device signup cap.
//
// When the peer is trusted it takes the right-most X-Forwarded-For entry — the
// address the trusted proxy itself appended — rather than the left-most, which
// a client can prepend.
func clientIP(r *http.Request, trusted []netip.Prefix) string {
	peer, ok := peerAddr(r.RemoteAddr)
	if !ok {
		return r.RemoteAddr
	}
	if !isTrusted(peer, trusted) {
		return peer.String()
	}
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		parts := strings.Split(xff, ",")
		for i := len(parts) - 1; i >= 0; i-- {
			if candidate := strings.TrimSpace(parts[i]); candidate != "" {
				return candidate
			}
		}
	}
	return peer.String()
}

// peerAddr extracts the address from a host:port RemoteAddr.
func peerAddr(remoteAddr string) (netip.Addr, bool) {
	host := remoteAddr
	if i := strings.LastIndex(remoteAddr, ":"); i >= 0 {
		host = remoteAddr[:i]
		host = strings.Trim(host, "[]")
	}
	addr, err := netip.ParseAddr(host)
	if err != nil {
		return netip.Addr{}, false
	}
	return addr.Unmap(), true
}

// isTrusted reports whether addr falls inside any trusted prefix.
func isTrusted(addr netip.Addr, trusted []netip.Prefix) bool {
	for _, prefix := range trusted {
		if prefix.Contains(addr) {
			return true
		}
	}
	return false
}

// hashIP turns a client IP into a stable, non-reversible device key for the
// free-account cap. The secret salts the hash so the table never stores a raw
// address.
func hashIP(secret, ip string) string {
	sum := sha256.Sum256([]byte(secret + "|" + ip))
	return hex.EncodeToString(sum[:])
}
