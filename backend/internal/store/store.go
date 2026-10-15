package store

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
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

// User is an app account, keyed by the client's random install id. GoogleSub
// is set only once the account has signed in with Google; it is the stable
// identity that survives reinstalls.
type User struct {
	ID        string
	InstallID string
	GoogleSub *string
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
    RETURNING id::text AS id, install_id, google_sub, created_at, true AS created
)
SELECT id, install_id, google_sub, created_at, created FROM ins
UNION ALL
SELECT id::text, install_id, google_sub, created_at, false FROM users WHERE install_id = $1
ORDER BY created DESC
LIMIT 1`
	var (
		u       User
		created bool
	)
	if err := s.pool.QueryRow(ctx, q, installID).
		Scan(&u.ID, &u.InstallID, &u.GoogleSub, &u.CreatedAt, &created); err != nil {
		return User{}, false, fmt.Errorf("create or get user: %w", err)
	}
	return u, created, nil
}

// UserByInstallID loads the account for a device, returning ErrNotFound when
// the device has never signed in.
func (s *Store) UserByInstallID(ctx context.Context, installID string) (User, error) {
	const q = `SELECT id::text, install_id, google_sub, created_at FROM users WHERE install_id = $1`
	var u User
	if err := s.pool.QueryRow(ctx, q, installID).Scan(&u.ID, &u.InstallID, &u.GoogleSub, &u.CreatedAt); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return User{}, ErrNotFound
		}
		return User{}, fmt.Errorf("load user by install id: %w", err)
	}
	return u, nil
}

// UserByID loads a single account, returning ErrNotFound when it is absent.
func (s *Store) UserByID(ctx context.Context, id string) (User, error) {
	const q = `SELECT id::text, install_id, google_sub, created_at FROM users WHERE id = $1::uuid`
	var u User
	if err := s.pool.QueryRow(ctx, q, id).Scan(&u.ID, &u.InstallID, &u.GoogleSub, &u.CreatedAt); err != nil {
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

// UsageTodayByKind sums today's units for a user, keyed by kind, in a single
// query so a per-kind remaining-limits view does not fan out into N queries.
func (s *Store) UsageTodayByKind(ctx context.Context, userID string) (map[string]float64, error) {
	const q = `
SELECT kind, SUM(units) FROM usage
WHERE user_id = $1::uuid AND created_at >= current_date
GROUP BY kind`
	rows, err := s.pool.Query(ctx, q, userID)
	if err != nil {
		return nil, fmt.Errorf("sum usage by kind: %w", err)
	}
	defer rows.Close()

	out := make(map[string]float64)
	for rows.Next() {
		var (
			kind  string
			total float64
		)
		if err := rows.Scan(&kind, &total); err != nil {
			return nil, fmt.Errorf("scan usage by kind: %w", err)
		}
		out[kind] = total
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("read usage by kind: %w", err)
	}
	return out, nil
}

// CreateUserIfAllowed returns the account for installID, creating it on first
// sight, and enforces the per-device free-account cap without ever burning the
// allowance for a device that ends up with no account.
//
// For an existing device it returns the account and does not touch the cap.
// For a new device the insert, the signup counter increment and the cap check
// share one transaction: when the cap is exceeded the whole transaction rolls
// back, so a rejected or failed creation leaves no user and no counter bump. A
// retry after a transient failure therefore still succeeds. The boolean
// reports whether a new account was created; allowed reports whether the
// caller may hand out a session for it.
func (s *Store) CreateUserIfAllowed(ctx context.Context, installID, ipHash string, cap int) (user User, created, allowed bool, err error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return User{}, false, false, fmt.Errorf("begin signup tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	row := tx.QueryRow(ctx,
		`INSERT INTO users (install_id) VALUES ($1)
		 ON CONFLICT (install_id) DO NOTHING
		 RETURNING id::text, install_id, google_sub, created_at`, installID)
	if scanErr := row.Scan(&user.ID, &user.InstallID, &user.GoogleSub, &user.CreatedAt); scanErr != nil {
		if !errors.Is(scanErr, pgx.ErrNoRows) {
			return User{}, false, false, fmt.Errorf("create user: %w", scanErr)
		}
		// The device already has an account: sign in without counting.
		if err := tx.QueryRow(ctx,
			`SELECT id::text, install_id, google_sub, created_at FROM users WHERE install_id = $1`, installID).
			Scan(&user.ID, &user.InstallID, &user.GoogleSub, &user.CreatedAt); err != nil {
			return User{}, false, false, fmt.Errorf("load existing user: %w", err)
		}
		if err := tx.Commit(ctx); err != nil {
			return User{}, false, false, fmt.Errorf("commit signup tx: %w", err)
		}
		return user, false, true, nil
	}

	// A brand-new account: count it, and roll back entirely if over the cap.
	var count int
	if err := tx.QueryRow(ctx,
		`INSERT INTO device_signups (ip_hash, day, count) VALUES ($1, current_date, 1)
		 ON CONFLICT (ip_hash, day) DO UPDATE SET count = device_signups.count + 1
		 RETURNING count`, ipHash).Scan(&count); err != nil {
		return User{}, false, false, fmt.Errorf("count signup: %w", err)
	}
	if count > cap {
		// Rolled back by the deferred Rollback: no user, no counter bump.
		return User{}, false, false, nil
	}
	if err := tx.Commit(ctx); err != nil {
		return User{}, false, false, fmt.Errorf("commit signup tx: %w", err)
	}
	return user, true, true, nil
}

// GoogleSignIn resolves a verified Google subject to an account, creating or
// linking one as needed, and reports whether an existing account was linked.
//
// Precedence:
//  1. an account already carrying this google_sub is returned (returning user);
//  2. otherwise, when linkUserID names an account with no google_sub, the
//     subject is attached to that same account so its usage history and any
//     RevenueCat entitlement stay linked (linked=true);
//  3. otherwise a new account is created for the subject.
//
// It runs in one transaction. Two concurrent requests for the same new subject
// race on the unique index over google_sub: the losing INSERT does nothing and
// the loser re-reads the winner's account, so a subject never ends up with two
// accounts. The unique install_id is handled the same way, falling back to
// linking the device's existing account.
func (s *Store) GoogleSignIn(ctx context.Context, sub, installID, linkUserID string) (User, bool, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return User{}, false, fmt.Errorf("begin google sign-in tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// 1. Returning account for this subject.
	if u, found, err := googleUserBySub(ctx, tx, sub); err != nil {
		return User{}, false, err
	} else if found {
		if err := tx.Commit(ctx); err != nil {
			return User{}, false, fmt.Errorf("commit google sign-in tx: %w", err)
		}
		return u, false, nil
	}

	// 2. Link the anonymous account whose session this request carried.
	if linkUserID != "" {
		u, updated, err := linkGoogleSub(ctx, tx, sub, linkUserID)
		if err != nil {
			return User{}, false, err
		}
		if updated {
			if err := tx.Commit(ctx); err != nil {
				return User{}, false, fmt.Errorf("commit google sign-in tx: %w", err)
			}
			return u, true, nil
		}
		// Could not attach the subject (a concurrent request claimed it, or the
		// account already moved on). Drop this transaction and settle from a
		// fresh connection.
		_ = tx.Rollback(ctx)
		return s.resolveGoogleConflict(ctx, sub, installID)
	}

	// 3. New account for this subject.
	u, inserted, err := insertGoogleUser(ctx, tx, installID, sub)
	if err != nil {
		return User{}, false, err
	}
	if !inserted {
		// Lost a race on google_sub or install_id.
		_ = tx.Rollback(ctx)
		return s.resolveGoogleConflict(ctx, sub, installID)
	}
	if err := tx.Commit(ctx); err != nil {
		return User{}, false, fmt.Errorf("commit google sign-in tx: %w", err)
	}
	return u, false, nil
}

// resolveGoogleConflict settles a Google sign-in that raced another writer on a
// unique constraint, using the pool outside any transaction. The subject is the
// stronger identity, so a subject owner wins; otherwise the install id's
// existing, subject-less account is linked.
func (s *Store) resolveGoogleConflict(ctx context.Context, sub, installID string) (User, bool, error) {
	if u, found, err := googleUserBySub(ctx, s.pool, sub); err != nil {
		return User{}, false, err
	} else if found {
		return u, false, nil
	}

	existing, err := s.UserByInstallID(ctx, installID)
	if err != nil && !errors.Is(err, ErrNotFound) {
		return User{}, false, err
	}
	if err == nil && existing.GoogleSub == nil {
		if u, updated, err := linkGoogleSub(ctx, s.pool, sub, existing.ID); err != nil {
			return User{}, false, err
		} else if updated {
			return u, true, nil
		}
	}

	// Another writer may have settled it between the checks above.
	if u, found, err := googleUserBySub(ctx, s.pool, sub); err != nil {
		return User{}, false, err
	} else if found {
		return u, false, nil
	}
	return User{}, false, fmt.Errorf("google sign-in: could not resolve subject")
}

// rowQuerier is the subset of pgx shared by the pool and a transaction, so the
// Google helpers work both inside a transaction and directly on the pool.
type rowQuerier interface {
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// googleUserBySub loads the account that owns a Google subject.
func googleUserBySub(ctx context.Context, q rowQuerier, sub string) (User, bool, error) {
	const stmt = `SELECT id::text, install_id, google_sub, created_at FROM users WHERE google_sub = $1`
	var u User
	err := q.QueryRow(ctx, stmt, sub).Scan(&u.ID, &u.InstallID, &u.GoogleSub, &u.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, false, nil
	}
	if err != nil {
		return User{}, false, fmt.Errorf("load user by google sub: %w", err)
	}
	return u, true, nil
}

// linkGoogleSub attaches a subject to a subject-less account. It reports false
// when the account does not exist or already carries a subject; a unique
// violation (the subject was claimed concurrently) is reported the same way.
func linkGoogleSub(ctx context.Context, q rowQuerier, sub, userID string) (User, bool, error) {
	const stmt = `UPDATE users SET google_sub = $1
	 WHERE id = $2::uuid AND google_sub IS NULL
	 RETURNING id::text, install_id, google_sub, created_at`
	var u User
	err := q.QueryRow(ctx, stmt, sub, userID).Scan(&u.ID, &u.InstallID, &u.GoogleSub, &u.CreatedAt)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		return User{}, false, nil
	case isUniqueViolation(err):
		return User{}, false, nil
	case err != nil:
		return User{}, false, fmt.Errorf("link google sub: %w", err)
	}
	return u, true, nil
}

// insertGoogleUser creates an account for a subject. It reports false when a
// unique constraint (either google_sub or install_id) was violated, leaving the
// caller to resolve the winner.
func insertGoogleUser(ctx context.Context, q rowQuerier, installID, sub string) (User, bool, error) {
	const stmt = `INSERT INTO users (install_id, google_sub) VALUES ($1, $2)
	 ON CONFLICT DO NOTHING
	 RETURNING id::text, install_id, google_sub, created_at`
	var u User
	err := q.QueryRow(ctx, stmt, installID, sub).Scan(&u.ID, &u.InstallID, &u.GoogleSub, &u.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, false, nil
	}
	if err != nil {
		return User{}, false, fmt.Errorf("insert google user: %w", err)
	}
	return u, true, nil
}

// isUniqueViolation reports whether err is a Postgres unique-constraint error.
func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

// ApplyEntitlementEvent records a RevenueCat event and applies its entitlement
// change in one transaction. It reports whether the event was newly applied;
// false means it was a duplicate that was already processed. Recording and
// applying together means a failure rolls both back, so a retry re-applies
// instead of being dismissed as a duplicate.
func (s *Store) ApplyEntitlementEvent(ctx context.Context, eventID string, payload []byte, e Entitlement) (bool, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return false, fmt.Errorf("begin entitlement tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	tag, err := tx.Exec(ctx,
		`INSERT INTO revenuecat_events (event_id, payload) VALUES ($1, $2) ON CONFLICT (event_id) DO NOTHING`,
		eventID, payload)
	if err != nil {
		return false, fmt.Errorf("record revenuecat event: %w", err)
	}
	if tag.RowsAffected() == 0 {
		// Already applied by an earlier delivery.
		return false, nil
	}

	if _, err := tx.Exec(ctx,
		`INSERT INTO entitlements (user_id, entitlement, status, expires_at, updated_at)
		 VALUES ($1::uuid, $2, $3, $4, now())
		 ON CONFLICT (user_id) DO UPDATE SET
		     entitlement = EXCLUDED.entitlement,
		     status = EXCLUDED.status,
		     expires_at = EXCLUDED.expires_at,
		     updated_at = now()`,
		e.UserID, e.Entitlement, e.Status, e.ExpiresAt); err != nil {
		return false, fmt.Errorf("upsert entitlement: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return false, fmt.Errorf("commit entitlement tx: %w", err)
	}
	return true, nil
}
