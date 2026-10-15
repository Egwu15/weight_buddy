package httpapi

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net"
	"net/http"
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

// clientIP resolves the caller's address, honouring the left-most
// X-Forwarded-For hop that Caddy adds in front of the service.
func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		first := xff
		if i := strings.IndexByte(xff, ','); i >= 0 {
			first = xff[:i]
		}
		if ip := strings.TrimSpace(first); ip != "" {
			return ip
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// hashIP turns a client IP into a stable, non-reversible device key for the
// free-account cap. The secret salts the hash so the table never stores a raw
// address.
func hashIP(secret, ip string) string {
	sum := sha256.Sum256([]byte(secret + "|" + ip))
	return hex.EncodeToString(sum[:])
}
