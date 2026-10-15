package httpapi

import (
	"context"

	"github.com/tedif/weight-buddy-backend/internal/store"
)

// Store is the subset of the persistence layer the HTTP layer depends on.
// Handlers take this interface so tests can supply a fake without a database.
type Store interface {
	UserByInstallID(ctx context.Context, installID string) (store.User, error)
	UserByID(ctx context.Context, id string) (store.User, error)
	CreateOrGetUser(ctx context.Context, installID string) (store.User, bool, error)
	RegisterSignup(ctx context.Context, ipHash string, cap int) (bool, error)

	Entitlement(ctx context.Context, userID string) (store.Entitlement, error)
	UpsertEntitlement(ctx context.Context, e store.Entitlement) error
	RecordRevenueCatEvent(ctx context.Context, eventID string, payload []byte) (bool, error)

	UsageToday(ctx context.Context, userID, kind string) (float64, error)
	RecordUsage(ctx context.Context, userID, kind string, units, cost float64) error
	DailySpend(ctx context.Context) (float64, error)
}
