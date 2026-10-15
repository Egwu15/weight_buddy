package store

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNotFound is returned when a lookup finds no matching row. Callers compare
// against it instead of leaking pgx's own sentinel upwards.
var ErrNotFound = errors.New("store: not found")

// Store is the Postgres persistence layer. All queries are hand-written; there
// is no ORM.
type Store struct {
	pool *pgxpool.Pool
}

// Open connects to Postgres and verifies the connection with a ping, so a bad
// DATABASE_URL fails at startup rather than on the first request.
func Open(ctx context.Context, databaseURL string) (*Store, error) {
	cfg, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, fmt.Errorf("parse DATABASE_URL: %w", err)
	}
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("connect to postgres: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping postgres: %w", err)
	}
	return &Store{pool: pool}, nil
}

// Close releases every pooled connection.
func (s *Store) Close() { s.pool.Close() }

// Pool exposes the underlying pool for the migration command and tests.
func (s *Store) Pool() *pgxpool.Pool { return s.pool }

// User is an app account, keyed by the client's random install id.
type User struct {
	ID        string
	InstallID string
	CreatedAt time.Time
}

// Entitlement is the single entitlement row kept per user, mirrored from
// RevenueCat. Status is one of active, grace, expired or cancelled_active.
type Entitlement struct {
	UserID      string
	Entitlement string
	Status      string
	ExpiresAt   *time.Time
	UpdatedAt   time.Time
}

// IsActive reports whether the entitlement currently grants paid limits:
// active, in its grace period, or cancelled but still inside the paid period,
// and not past its expiry.
func (e Entitlement) IsActive(now time.Time) bool {
	switch e.Status {
	case "active", "grace", "cancelled_active":
	default:
		return false
	}
	return e.ExpiresAt == nil || e.ExpiresAt.After(now)
}

// CreateOrGetUser returns the account for installID, creating it on first
// sight. The boolean reports whether this call created a new account, which is
// what the per-device free-account cap counts.
func (s *Store) CreateOrGetUser(ctx context.Context, installID string) (User, bool, error) {
	const q = `
WITH ins AS (
    INSERT INTO users (install_id)
    VALUES ($1)
    ON CONFLICT (install_id) DO NOTHING
    RETURNING id::text AS id, install_id, created_at, true AS created
)
SELECT id, install_id, created_at, created FROM ins
UNION ALL
SELECT id::text, install_id, created_at, false FROM users WHERE install_id = $1
ORDER BY created DESC
LIMIT 1`
	var (
		u       User
		created bool
	)
	if err := s.pool.QueryRow(ctx, q, installID).
		Scan(&u.ID, &u.InstallID, &u.CreatedAt, &created); err != nil {
		return User{}, false, fmt.Errorf("create or get user: %w", err)
	}
	return u, created, nil
}

// UserByInstallID loads the account for a device, returning ErrNotFound when
// the device has never signed in.
func (s *Store) UserByInstallID(ctx context.Context, installID string) (User, error) {
	const q = `SELECT id::text, install_id, created_at FROM users WHERE install_id = $1`
	var u User
	if err := s.pool.QueryRow(ctx, q, installID).Scan(&u.ID, &u.InstallID, &u.CreatedAt); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return User{}, ErrNotFound
		}
		return User{}, fmt.Errorf("load user by install id: %w", err)
	}
	return u, nil
}

// UserByID loads a single account, returning ErrNotFound when it is absent.
func (s *Store) UserByID(ctx context.Context, id string) (User, error) {
	const q = `SELECT id::text, install_id, created_at FROM users WHERE id = $1::uuid`
	var u User
	if err := s.pool.QueryRow(ctx, q, id).Scan(&u.ID, &u.InstallID, &u.CreatedAt); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return User{}, ErrNotFound
		}
		return User{}, fmt.Errorf("load user: %w", err)
	}
	return u, nil
}

// Entitlement loads the entitlement row for a user, returning ErrNotFound when
// the user has never had one (i.e. is on the free tier).
func (s *Store) Entitlement(ctx context.Context, userID string) (Entitlement, error) {
	const q = `
SELECT user_id::text, entitlement, status, expires_at, updated_at
FROM entitlements WHERE user_id = $1::uuid`
	var e Entitlement
	if err := s.pool.QueryRow(ctx, q, userID).
		Scan(&e.UserID, &e.Entitlement, &e.Status, &e.ExpiresAt, &e.UpdatedAt); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Entitlement{}, ErrNotFound
		}
		return Entitlement{}, fmt.Errorf("load entitlement: %w", err)
	}
	return e, nil
}

// UpsertEntitlement writes the latest entitlement state for a user.
func (s *Store) UpsertEntitlement(ctx context.Context, e Entitlement) error {
	const q = `
INSERT INTO entitlements (user_id, entitlement, status, expires_at, updated_at)
VALUES ($1::uuid, $2, $3, $4, now())
ON CONFLICT (user_id) DO UPDATE SET
    entitlement = EXCLUDED.entitlement,
    status = EXCLUDED.status,
    expires_at = EXCLUDED.expires_at,
    updated_at = now()`
	if _, err := s.pool.Exec(ctx, q, e.UserID, e.Entitlement, e.Status, e.ExpiresAt); err != nil {
		return fmt.Errorf("upsert entitlement: %w", err)
	}
	return nil
}

// RecordRevenueCatEvent stores a webhook payload for idempotency. It reports
// whether the event was newly inserted; false means it was a duplicate and the
// caller should skip processing.
func (s *Store) RecordRevenueCatEvent(ctx context.Context, eventID string, payload []byte) (bool, error) {
	const q = `INSERT INTO revenuecat_events (event_id, payload) VALUES ($1, $2) ON CONFLICT (event_id) DO NOTHING`
	tag, err := s.pool.Exec(ctx, q, eventID, payload)
	if err != nil {
		return false, fmt.Errorf("record revenuecat event: %w", err)
	}
	return tag.RowsAffected() == 1, nil
}

// RecordUsage appends a usage row and adds its cost to the global spend tally
// for today, in one transaction so the two never drift apart.
func (s *Store) RecordUsage(ctx context.Context, userID, kind string, units, cost float64) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin usage tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx,
		`INSERT INTO usage (user_id, kind, units, cost_estimate) VALUES ($1::uuid, $2, $3, $4)`,
		userID, kind, units, cost); err != nil {
		return fmt.Errorf("insert usage: %w", err)
	}
	if _, err := tx.Exec(ctx,
		`INSERT INTO daily_spend (day, cost_estimate) VALUES (current_date, $1)
		 ON CONFLICT (day) DO UPDATE SET cost_estimate = daily_spend.cost_estimate + EXCLUDED.cost_estimate`,
		cost); err != nil {
		return fmt.Errorf("update daily spend: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit usage tx: %w", err)
	}
	return nil
}

// UsageToday sums the units recorded for a user and kind since local midnight.
func (s *Store) UsageToday(ctx context.Context, userID, kind string) (float64, error) {
	const q = `
SELECT COALESCE(SUM(units), 0) FROM usage
WHERE user_id = $1::uuid AND kind = $2 AND created_at >= current_date`
	var total float64
	if err := s.pool.QueryRow(ctx, q, userID, kind).Scan(&total); err != nil {
		return 0, fmt.Errorf("sum usage: %w", err)
	}
	return total, nil
}

// DailySpend returns today's global spend estimate, zero when nothing is spent.
func (s *Store) DailySpend(ctx context.Context) (float64, error) {
	const q = `SELECT COALESCE((SELECT cost_estimate FROM daily_spend WHERE day = current_date), 0)`
	var total float64
	if err := s.pool.QueryRow(ctx, q).Scan(&total); err != nil {
		return 0, fmt.Errorf("read daily spend: %w", err)
	}
	return total, nil
}

// RegisterSignup increments today's signup counter for a device and reports
// whether the count is still within the cap.
func (s *Store) RegisterSignup(ctx context.Context, ipHash string, cap int) (bool, error) {
	const q = `
INSERT INTO device_signups (ip_hash, day, count) VALUES ($1, current_date, 1)
ON CONFLICT (ip_hash, day) DO UPDATE SET count = device_signups.count + 1
RETURNING count`
	var count int
	if err := s.pool.QueryRow(ctx, q, ipHash).Scan(&count); err != nil {
		return false, fmt.Errorf("register signup: %w", err)
	}
	return count <= cap, nil
}
