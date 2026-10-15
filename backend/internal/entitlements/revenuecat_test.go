package entitlements

import (
	"testing"
	"time"
)

func ms(t time.Time) *int64 {
	v := t.UnixMilli()
	return &v
}

func TestDecide(t *testing.T) {
	now := time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)
	future := now.Add(7 * 24 * time.Hour)
	past := now.Add(-time.Hour)

	tests := []struct {
		name      string
		event     Event
		wantOK    bool
		wantStat  string
		wantEntit string
		wantExp   *time.Time
	}{
		{
			name:      "initial purchase is active",
			event:     Event{Type: TypeInitialPurchase, EntitlementIDs: []string{"pro"}, ExpirationAtMs: ms(future)},
			wantOK:    true,
			wantStat:  StatusActive,
			wantEntit: "pro",
			wantExp:   &future,
		},
		{
			name:      "renewal is active",
			event:     Event{Type: TypeRenewal, EntitlementIDs: []string{"pro"}, ExpirationAtMs: ms(future)},
			wantOK:    true,
			wantStat:  StatusActive,
			wantEntit: "pro",
			wantExp:   &future,
		},
		{
			name:      "uncancellation is active",
			event:     Event{Type: TypeUncancellation, EntitlementIDs: []string{"pro"}, ExpirationAtMs: ms(future)},
			wantOK:    true,
			wantStat:  StatusActive,
			wantEntit: "pro",
			wantExp:   &future,
		},
		{
			name:      "cancellation before expiry is cancelled_active",
			event:     Event{Type: TypeCancellation, EntitlementIDs: []string{"pro"}, ExpirationAtMs: ms(future)},
			wantOK:    true,
			wantStat:  StatusCancelledActive,
			wantEntit: "pro",
			wantExp:   &future,
		},
		{
			name:      "cancellation after expiry is expired",
			event:     Event{Type: TypeCancellation, EntitlementIDs: []string{"pro"}, ExpirationAtMs: ms(past)},
			wantOK:    true,
			wantStat:  StatusExpired,
			wantEntit: "pro",
			wantExp:   &past,
		},
		{
			name:      "expiration is expired",
			event:     Event{Type: TypeExpiration, EntitlementIDs: []string{"pro"}, ExpirationAtMs: ms(past)},
			wantOK:    true,
			wantStat:  StatusExpired,
			wantEntit: "pro",
			wantExp:   &past,
		},
		{
			name:      "billing issue is grace",
			event:     Event{Type: TypeBillingIssue, EntitlementIDs: []string{"pro"}, GracePeriodExpirationAtMs: ms(future)},
			wantOK:    true,
			wantStat:  StatusGrace,
			wantEntit: "pro",
			wantExp:   &future,
		},
		{
			name:      "product change is active",
			event:     Event{Type: TypeProductChange, EntitlementIDs: []string{"pro"}, ExpirationAtMs: ms(future)},
			wantOK:    true,
			wantStat:  StatusActive,
			wantEntit: "pro",
			wantExp:   &future,
		},
		{
			name:      "fallback entitlement id from config",
			event:     Event{Type: TypeInitialPurchase, ExpirationAtMs: ms(future)},
			wantOK:    true,
			wantStat:  StatusActive,
			wantEntit: "configured",
			wantExp:   &future,
		},
		{
			name:   "transfer carries no entitlement change",
			event:  Event{Type: TypeTransfer, TransferredTo: []string{"someone"}},
			wantOK: false,
		},
		{
			name:   "unknown type carries no entitlement change",
			event:  Event{Type: TypeExperimentEnrollment},
			wantOK: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := Decide(tt.event, "configured", now)
			if ok != tt.wantOK {
				t.Fatalf("ok = %v, want %v", ok, tt.wantOK)
			}
			if !ok {
				return
			}
			if got.Status != tt.wantStat {
				t.Fatalf("status = %q, want %q", got.Status, tt.wantStat)
			}
			if got.Entitlement != tt.wantEntit {
				t.Fatalf("entitlement = %q, want %q", got.Entitlement, tt.wantEntit)
			}
			if tt.wantExp == nil {
				if got.ExpiresAt != nil {
					t.Fatalf("expiry = %v, want nil", got.ExpiresAt)
				}
			} else if got.ExpiresAt == nil || !got.ExpiresAt.Equal(*tt.wantExp) {
				t.Fatalf("expiry = %v, want %v", got.ExpiresAt, tt.wantExp)
			}
		})
	}
}
