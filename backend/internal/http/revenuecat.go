package httpapi

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/tedif/weight-buddy-backend/internal/entitlements"
	"github.com/tedif/weight-buddy-backend/internal/store"
)

// maxWebhookBody caps the webhook body. RevenueCat payloads are small; this is
// a safety net, not a real limit.
const maxWebhookBody = 1 << 20

// handleRevenueCatWebhook receives subscription lifecycle notifications. It is
// authenticated by a shared secret in the Authorization header, compared in
// constant time, and is idempotent on the event id so RevenueCat's retries
// cannot double-apply a change.
func (d Deps) handleRevenueCatWebhook(w http.ResponseWriter, r *http.Request) {
	if d.RevenueCatWebhookSecret == "" {
		writeError(w, http.StatusServiceUnavailable, "not_configured", "Webhooks are not configured.")
		return
	}

	provided := strings.TrimSpace(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
	if subtle.ConstantTimeCompare([]byte(provided), []byte(d.RevenueCatWebhookSecret)) != 1 {
		writeError(w, http.StatusUnauthorized, "unauthorized", "Invalid webhook authorization.")
		return
	}

	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxWebhookBody))
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Could not read the webhook body.")
		return
	}

	var payload entitlements.Payload
	if err := json.Unmarshal(body, &payload); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "The webhook body is not valid JSON.")
		return
	}
	if payload.Event.ID == "" {
		writeError(w, http.StatusBadRequest, "invalid_request", "The webhook event is missing an id.")
		return
	}

	ctx := r.Context()
	inserted, err := d.Store.RecordRevenueCatEvent(ctx, payload.Event.ID, body)
	if err != nil {
		d.serverError(w, r, err)
		return
	}
	if !inserted {
		writeJSON(w, http.StatusOK, map[string]string{"status": "duplicate"})
		return
	}

	user, err := d.resolveWebhookUser(ctx, payload.Event)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			// An event for a subscriber we do not know: acknowledge so
			// RevenueCat stops retrying, and move on.
			writeJSON(w, http.StatusOK, map[string]string{"status": "unknown_user"})
			return
		}
		d.serverError(w, r, err)
		return
	}

	state, changed := entitlements.Decide(payload.Event, d.RevenueCatEntitlementID, time.Now())
	if !changed {
		writeJSON(w, http.StatusOK, map[string]string{"status": "recorded"})
		return
	}

	if err := d.Store.UpsertEntitlement(ctx, store.Entitlement{
		UserID:      user.ID,
		Entitlement: state.Entitlement,
		Status:      state.Status,
		ExpiresAt:   state.ExpiresAt,
	}); err != nil {
		d.serverError(w, r, err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// resolveWebhookUser finds the account an event refers to. It searches the
// app user id, the original app user id and every alias, since RevenueCat may
// report any of them after an identity changes.
func (d Deps) resolveWebhookUser(ctx context.Context, e entitlements.Event) (store.User, error) {
	candidates := make([]string, 0, 2+len(e.Aliases))
	candidates = append(candidates, e.AppUserID, e.OriginalAppUserID)
	candidates = append(candidates, e.Aliases...)

	for _, id := range candidates {
		if !looksLikeUserID(id) {
			continue
		}
		user, err := d.Store.UserByID(ctx, id)
		switch {
		case err == nil:
			return user, nil
		case errors.Is(err, store.ErrNotFound):
			continue
		default:
			return store.User{}, err
		}
	}
	return store.User{}, store.ErrNotFound
}

// looksLikeUserID keeps a non-UUID RevenueCat id (e.g. an
// `$RCAnonymousID:...`) out of a `$1::uuid` query, which would otherwise error.
func looksLikeUserID(s string) bool {
	if len(s) != 36 {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if i == 8 || i == 13 || i == 18 || i == 23 {
			if c != '-' {
				return false
			}
			continue
		}
		isHex := (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
		if !isHex {
			return false
		}
	}
	return true
}
