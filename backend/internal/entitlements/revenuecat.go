// Package entitlements maps RevenueCat events to per-user entitlement state.
package entitlements

import "time"

// RevenueCat webhook event types this service acts on. Types are the exact
// `type` strings from the RevenueCat webhook payload.
const (
	TypeInitialPurchase       = "INITIAL_PURCHASE"
	TypeRenewal               = "RENEWAL"
	TypeCancellation          = "CANCELLATION"
	TypeUncancellation        = "UNCANCELLATION"
	TypeNonRenewingPurchase   = "NON_RENEWING_PURCHASE"
	TypeSubscriptionPaused    = "SUBSCRIPTION_PAUSED"
	TypeExpiration            = "EXPIRATION"
	TypeBillingIssue          = "BILLING_ISSUE"
	TypeProductChange         = "PRODUCT_CHANGE"
	TypeSubscriptionExtended  = "SUBSCRIPTION_EXTENDED"
	TypeRefundReversed        = "REFUND_REVERSED"
	TypeTemporaryEntitlement  = "TEMPORARY_ENTITLEMENT_GRANT"
	TypeTransfer              = "TRANSFER"
	TypeSubscriberAlias       = "SUBSCRIBER_ALIAS"
	TypeTest                  = "TEST"
	TypeExperimentEnrollment  = "EXPERIMENT_ENROLLMENT"
	TypeVirtualCurrency       = "VIRTUAL_CURRENCY_TRANSACTION"
	TypePurchaseRedeemed      = "PURCHASE_REDEEMED"
	TypePriceIncreaseRequired = "PRICE_INCREASE_CONSENT_REQUIRED"
	TypePriceIncreaseApproved = "PRICE_INCREASE_CONSENT_APPROVED"
	TypeInvoiceIssuance       = "INVOICE_ISSUANCE"
)

// Statuses stored on the entitlement row.
const (
	StatusActive          = "active"
	StatusGrace           = "grace"
	StatusExpired         = "expired"
	StatusCancelledActive = "cancelled_active"
)

// Event is the subset of a RevenueCat webhook event this service reads. The
// full payload is stored verbatim for idempotency, so unlisted fields are
// preserved even though the struct ignores them.
//
// Fields documented as "Sometimes" are optional, so most are pointers or
// slices; parse defensively.
type Event struct {
	ID                        string   `json:"id"`
	Type                      string   `json:"type"`
	AppUserID                 string   `json:"app_user_id"`
	OriginalAppUserID         string   `json:"original_app_user_id"`
	Aliases                   []string `json:"aliases"`
	EntitlementIDs            []string `json:"entitlement_ids"`
	ExpirationAtMs            *int64   `json:"expiration_at_ms"`
	GracePeriodExpirationAtMs *int64   `json:"grace_period_expiration_at_ms"`
	TransferredFrom           []string `json:"transferred_from"`
	TransferredTo             []string `json:"transferred_to"`
	Environment               string   `json:"environment"`
}

// Payload is the full webhook body: an API version plus one event.
type Payload struct {
	APIVersion string `json:"api_version"`
	Event      Event  `json:"event"`
}

// State is the entitlement state an event implies.
type State struct {
	Entitlement string
	Status      string
	ExpiresAt   *time.Time
}

// Decide maps an event to the entitlement state it implies. ok is false when
// the event carries no entitlement change (for example TRANSFER, or a type we
// do not act on) and should only be recorded for idempotency.
//
// defaultEntitlementID is used when an event carries no entitlement ids of its
// own; it comes from config so a single-entitlement app does not depend on the
// payload always naming it.
func Decide(e Event, defaultEntitlementID string, now time.Time) (State, bool) {
	entitlement := e.entitlement(defaultEntitlementID)

	switch e.Type {
	case TypeInitialPurchase,
		TypeRenewal,
		TypeUncancellation,
		TypeProductChange,
		TypeSubscriptionExtended,
		TypeRefundReversed,
		TypeTemporaryEntitlement:
		return State{Entitlement: entitlement, Status: StatusActive, ExpiresAt: msToTime(e.ExpirationAtMs)}, true

	case TypeNonRenewingPurchase, TypeInvoiceIssuance, TypePurchaseRedeemed:
		// One-off purchases keep access; a null expiry means it never lapses.
		return State{Entitlement: entitlement, Status: StatusActive, ExpiresAt: msToTime(e.ExpirationAtMs)}, true

	case TypeCancellation:
		// Cancelled but still inside the paid period -> cancelled_active;
		// otherwise the paid period is over -> expired.
		expires := msToTime(e.ExpirationAtMs)
		if expires != nil && expires.After(now) {
			return State{Entitlement: entitlement, Status: StatusCancelledActive, ExpiresAt: expires}, true
		}
		return State{Entitlement: entitlement, Status: StatusExpired, ExpiresAt: expires}, true

	case TypeBillingIssue:
		// The store could not charge; access continues through the grace
		// period when one is configured.
		expires := msToTime(e.GracePeriodExpirationAtMs)
		if expires == nil {
			expires = msToTime(e.ExpirationAtMs)
		}
		return State{Entitlement: entitlement, Status: StatusGrace, ExpiresAt: expires}, true

	case TypeExpiration, TypeSubscriptionPaused:
		return State{Entitlement: entitlement, Status: StatusExpired, ExpiresAt: msToTime(e.ExpirationAtMs)}, true

	default:
		return State{}, false
	}
}

func (e Event) entitlement(defaultID string) string {
	for _, id := range e.EntitlementIDs {
		if id != "" {
			return id
		}
	}
	if defaultID != "" {
		return defaultID
	}
	return "pro"
}

func msToTime(ms *int64) *time.Time {
	if ms == nil {
		return nil
	}
	t := time.UnixMilli(*ms).UTC()
	return &t
}
