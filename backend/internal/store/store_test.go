package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"sync"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"

	"github.com/tedif/weight-buddy-backend/migrations"
)

// testStore connects to the database named by TEST_DATABASE_URL, applies the
// migrations and starts each test from empty tables. It skips (rather than
// fails) when no database is configured, so `go test ./...` stays green on a
// machine without Postgres.
func testStore(t *testing.T) *Store {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL not set; skipping store integration tests")
	}

	db, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Fatalf("open database: %v", err)
	}
	goose.SetBaseFS(migrations.FS)
	if err := goose.SetDialect("postgres"); err != nil {
		t.Fatalf("set dialect: %v", err)
	}
	if err := goose.Up(db, "."); err != nil {
		t.Fatalf("apply migrations: %v", err)
	}
	_ = db.Close()

	ctx := context.Background()
	s, err := Open(ctx, dsn)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(s.Close)
	if _, err := s.pool.Exec(ctx,
		`TRUNCATE users, entitlements, revenuecat_events, usage, daily_spend, device_signups`); err != nil {
		t.Fatalf("truncate: %v", err)
	}
	return s
}

func TestCreateOrGetUserIsIdempotent(t *testing.T) {
	s := testStore(t)
	ctx := context.Background()

	first, created, err := s.CreateOrGetUser(ctx, "install-1")
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if !created {
		t.Fatal("first sign-in should report created")
	}
	if first.ID == "" || first.InstallID != "install-1" {
		t.Fatalf("unexpected user %+v", first)
	}

	second, created, err := s.CreateOrGetUser(ctx, "install-1")
	if err != nil {
		t.Fatalf("second create: %v", err)
	}
	if created {
		t.Fatal("repeat sign-in should not report created")
	}
	if second.ID != first.ID {
		t.Fatalf("id changed across sign-ins: %q vs %q", first.ID, second.ID)
	}
}

func TestEntitlementLifecycle(t *testing.T) {
	s := testStore(t)
	ctx := context.Background()

	u, _, err := s.CreateOrGetUser(ctx, "install-2")
	if err != nil {
		t.Fatalf("create user: %v", err)
	}

	if _, err := s.Entitlement(ctx, u.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound before any entitlement, got %v", err)
	}

	expiry := time.Now().Add(24 * time.Hour)
	if err := s.UpsertEntitlement(ctx, Entitlement{
		UserID:      u.ID,
		Entitlement: "pro",
		Status:      "active",
		ExpiresAt:   &expiry,
	}); err != nil {
		t.Fatalf("upsert: %v", err)
	}

	got, err := s.Entitlement(ctx, u.ID)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if !got.IsActive(time.Now()) {
		t.Fatalf("active entitlement should be active: %+v", got)
	}

	past := time.Now().Add(-time.Hour)
	got.Status = "expired"
	got.ExpiresAt = &past
	if got.IsActive(time.Now()) {
		t.Fatal("expired entitlement must not be active")
	}
}

func TestEntitlementIsActiveStatuses(t *testing.T) {
	now := time.Now()
	future := now.Add(time.Hour)
	past := now.Add(-time.Hour)

	tests := []struct {
		name string
		e    Entitlement
		want bool
	}{
		{"active no expiry", Entitlement{Status: "active"}, true},
		{"grace in period", Entitlement{Status: "grace", ExpiresAt: &future}, true},
		{"cancelled_active in period", Entitlement{Status: "cancelled_active", ExpiresAt: &future}, true},
		{"active but expired", Entitlement{Status: "active", ExpiresAt: &past}, false},
		{"expired status", Entitlement{Status: "expired", ExpiresAt: &future}, false},
		{"unknown status", Entitlement{Status: "billing_issue"}, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.e.IsActive(now); got != tt.want {
				t.Fatalf("IsActive = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestRecordRevenueCatEventIsIdempotent(t *testing.T) {
	s := testStore(t)
	ctx := context.Background()

	first, err := s.RecordRevenueCatEvent(ctx, "evt-1", []byte(`{"type":"INITIAL_PURCHASE"}`))
	if err != nil {
		t.Fatalf("record: %v", err)
	}
	if !first {
		t.Fatal("first event should be newly inserted")
	}

	second, err := s.RecordRevenueCatEvent(ctx, "evt-1", []byte(`{"type":"INITIAL_PURCHASE"}`))
	if err != nil {
		t.Fatalf("record duplicate: %v", err)
	}
	if second {
		t.Fatal("duplicate event should not be inserted again")
	}
}

func TestRecordUsageAndSpend(t *testing.T) {
	s := testStore(t)
	ctx := context.Background()

	u, _, err := s.CreateOrGetUser(ctx, "install-3")
	if err != nil {
		t.Fatalf("create user: %v", err)
	}

	if err := s.RecordUsage(ctx, u.ID, "transcribe", 1, 0.006); err != nil {
		t.Fatalf("record usage: %v", err)
	}
	if err := s.RecordUsage(ctx, u.ID, "transcribe", 2, 0.012); err != nil {
		t.Fatalf("record usage: %v", err)
	}
	if err := s.RecordUsage(ctx, u.ID, "parse_meal", 1, 0.001); err != nil {
		t.Fatalf("record usage: %v", err)
	}

	units, err := s.UsageToday(ctx, u.ID, "transcribe")
	if err != nil {
		t.Fatalf("usage today: %v", err)
	}
	if units != 3 {
		t.Fatalf("transcribe units = %v, want 3", units)
	}

	spend, err := s.DailySpend(ctx)
	if err != nil {
		t.Fatalf("daily spend: %v", err)
	}
	if spend < 0.0189 || spend > 0.0191 {
		t.Fatalf("daily spend = %v, want ~0.019", spend)
	}
}

func TestCreateUserIfAllowedHonoursCap(t *testing.T) {
	s := testStore(t)
	ctx := context.Background()

	// First device from an IP is created and allowed.
	u1, created, allowed, err := s.CreateUserIfAllowed(ctx, "device-a", "hash-a", 1)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if !created || !allowed {
		t.Fatalf("first signup created=%v allowed=%v, want true/true", created, allowed)
	}

	// A second, different device from the same IP exceeds the cap: it must not
	// be created and must not leave a row or bump the counter.
	_, created, allowed, err = s.CreateUserIfAllowed(ctx, "device-b", "hash-a", 1)
	if err != nil {
		t.Fatalf("create second: %v", err)
	}
	if created || allowed {
		t.Fatalf("over-cap signup created=%v allowed=%v, want false/false", created, allowed)
	}
	if _, err := s.UserByInstallID(ctx, "device-b"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("over-cap device should not exist, got %v", err)
	}

	// The same device signing in again is not counted and is always allowed.
	u2, created, allowed, err := s.CreateUserIfAllowed(ctx, "device-a", "hash-a", 1)
	if err != nil {
		t.Fatalf("re-signin: %v", err)
	}
	if created || !allowed || u2.ID != u1.ID {
		t.Fatalf("re-signin created=%v allowed=%v id-match=%v", created, allowed, u2.ID == u1.ID)
	}

	// A different IP has its own budget.
	_, created, allowed, err = s.CreateUserIfAllowed(ctx, "device-c", "hash-b", 1)
	if err != nil {
		t.Fatalf("create other ip: %v", err)
	}
	if !created || !allowed {
		t.Fatalf("fresh IP created=%v allowed=%v, want true/true", created, allowed)
	}
}

func TestApplyEntitlementEventIsAtomic(t *testing.T) {
	s := testStore(t)
	ctx := context.Background()

	u, _, err := s.CreateOrGetUser(ctx, "install-ent")
	if err != nil {
		t.Fatalf("create user: %v", err)
	}
	expiry := time.Now().Add(24 * time.Hour)

	applied, err := s.ApplyEntitlementEvent(ctx, "evt-a", []byte(`{"type":"INITIAL_PURCHASE"}`), Entitlement{
		UserID:      u.ID,
		Entitlement: "pro",
		Status:      "active",
		ExpiresAt:   &expiry,
	})
	if err != nil {
		t.Fatalf("apply: %v", err)
	}
	if !applied {
		t.Fatal("first delivery should apply")
	}
	got, err := s.Entitlement(ctx, u.ID)
	if err != nil || got.Status != "active" {
		t.Fatalf("entitlement = %+v, err=%v", got, err)
	}

	// A retry of the same event id is a no-op, not a re-application.
	applied, err = s.ApplyEntitlementEvent(ctx, "evt-a", []byte(`{"type":"INITIAL_PURCHASE"}`), Entitlement{
		UserID: u.ID, Entitlement: "pro", Status: "expired",
	})
	if err != nil {
		t.Fatalf("apply duplicate: %v", err)
	}
	if applied {
		t.Fatal("duplicate event should not re-apply")
	}
	got, _ = s.Entitlement(ctx, u.ID)
	if got.Status != "active" {
		t.Fatalf("duplicate changed state to %q", got.Status)
	}
}

func TestUsageTodayByKindGroupsRows(t *testing.T) {
	s := testStore(t)
	ctx := context.Background()

	u, _, err := s.CreateOrGetUser(ctx, "install-usage")
	if err != nil {
		t.Fatalf("create user: %v", err)
	}
	if err := s.RecordUsage(ctx, u.ID, "transcribe", 2, 0.01); err != nil {
		t.Fatalf("record: %v", err)
	}
	if err := s.RecordUsage(ctx, u.ID, "parse", 3, 0.02); err != nil {
		t.Fatalf("record: %v", err)
	}

	got, err := s.UsageTodayByKind(ctx, u.ID)
	if err != nil {
		t.Fatalf("usage by kind: %v", err)
	}
	if got["transcribe"] != 2 || got["parse"] != 3 {
		t.Fatalf("usage by kind = %+v, want transcribe 2 / parse 3", got)
	}
}

func TestGoogleSignInLinksPreservingAccount(t *testing.T) {
	s := testStore(t)
	ctx := context.Background()

	anon, _, err := s.CreateOrGetUser(ctx, "device-link")
	if err != nil {
		t.Fatalf("create anonymous: %v", err)
	}

	linked, isLinked, err := s.GoogleSignIn(ctx, "sub-link", "device-link", anon.ID)
	if err != nil {
		t.Fatalf("link: %v", err)
	}
	if !isLinked {
		t.Fatal("linking an anonymous account should report linked")
	}
	if linked.ID != anon.ID {
		t.Fatalf("linked id = %q, want the anonymous id %q", linked.ID, anon.ID)
	}
	if linked.GoogleSub == nil || *linked.GoogleSub != "sub-link" {
		t.Fatalf("google_sub = %v, want sub-link", linked.GoogleSub)
	}

	// Signing in again from a new install returns the same account, not linked.
	again, isLinked, err := s.GoogleSignIn(ctx, "sub-link", "device-new-install", "")
	if err != nil {
		t.Fatalf("returning: %v", err)
	}
	if isLinked {
		t.Fatal("a returning subject must not report linked")
	}
	if again.ID != anon.ID {
		t.Fatalf("returning id = %q, want %q", again.ID, anon.ID)
	}
}

func TestGoogleSignInSubjectOwnedByOtherUserIsNotMerged(t *testing.T) {
	s := testStore(t)
	ctx := context.Background()

	owner, _, err := s.GoogleSignIn(ctx, "sub-owned", "device-owner", "")
	if err != nil {
		t.Fatalf("create owner: %v", err)
	}
	anon, _, err := s.CreateOrGetUser(ctx, "device-other")
	if err != nil {
		t.Fatalf("create anonymous: %v", err)
	}

	got, isLinked, err := s.GoogleSignIn(ctx, "sub-owned", "device-other", anon.ID)
	if err != nil {
		t.Fatalf("sign in: %v", err)
	}
	if isLinked {
		t.Fatal("a subject already owned by another user must not report linked")
	}
	if got.ID != owner.ID {
		t.Fatalf("id = %q, want the subject owner %q", got.ID, owner.ID)
	}

	// The anonymous account is untouched: no subject was attached.
	reloaded, err := s.UserByID(ctx, anon.ID)
	if err != nil {
		t.Fatalf("reload anonymous: %v", err)
	}
	if reloaded.GoogleSub != nil {
		t.Fatalf("anonymous account was modified, google_sub = %v", *reloaded.GoogleSub)
	}
}

// TestGoogleSignInRaceCreatesOneUser fires many concurrent sign-ins for the same// new subject. The unique index must serialise them into a single account.
func TestGoogleSignInRaceCreatesOneUser(t *testing.T) {
	s := testStore(t)
	ctx := context.Background()

	const n = 8
	ids := make([]string, n)
	errs := make([]error, n)
	start := make(chan struct{})
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			u, _, err := s.GoogleSignIn(ctx, "sub-race", fmt.Sprintf("device-race-%d", i), "")
			ids[i] = u.ID
			errs[i] = err
		}(i)
	}
	close(start)
	wg.Wait()

	for i, err := range errs {
		if err != nil {
			t.Fatalf("call %d: %v", i, err)
		}
		if ids[i] != ids[0] {
			t.Fatalf("call %d returned user %q, want %q", i, ids[i], ids[0])
		}
	}

	// Exactly one account owns the subject.
	var count int
	if err := s.pool.QueryRow(ctx, `SELECT count(*) FROM users WHERE google_sub = $1`, "sub-race").Scan(&count); err != nil {
		t.Fatalf("count: %v", err)
	}
	if count != 1 {
		t.Fatalf("users with subject = %d, want 1", count)
	}
}

func TestDeleteUserRemovesAllRowsAndIsIdempotent(t *testing.T) {
	s := testStore(t)
	ctx := context.Background()

	user, _, err := s.GoogleSignIn(ctx, "sub-delete", "device-delete", "")
	if err != nil {
		t.Fatalf("create user: %v", err)
	}
	if err := s.UpsertEntitlement(ctx, Entitlement{
		UserID: user.ID, Entitlement: "pro", Status: "active",
	}); err != nil {
		t.Fatalf("upsert entitlement: %v", err)
	}
	if err := s.RecordUsage(ctx, user.ID, "transcribe", 2, 0.01); err != nil {
		t.Fatalf("record usage: %v", err)
	}
	event := []byte(`{"api_version":"1.0","event":{"id":"evt-del","type":"INITIAL_PURCHASE","app_user_id":"` + user.ID + `"}}`)
	if _, err := s.RecordRevenueCatEvent(ctx, "evt-del", event); err != nil {
		t.Fatalf("record event: %v", err)
	}
	// An event that references the user only through an alias must go too.
	aliasEvent := []byte(`{"api_version":"1.0","event":{"id":"evt-alias","type":"TRANSFER","aliases":["` + user.ID + `"]}}`)
	if _, err := s.RecordRevenueCatEvent(ctx, "evt-alias", aliasEvent); err != nil {
		t.Fatalf("record alias event: %v", err)
	}

	deleted, err := s.DeleteUser(ctx, user.ID)
	if err != nil {
		t.Fatalf("delete: %v", err)
	}
	if !deleted {
		t.Fatal("delete should report the account existed")
	}

	if _, err := s.UserByID(ctx, user.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("user still present: %v", err)
	}
	if _, err := s.Entitlement(ctx, user.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("entitlement still present: %v", err)
	}
	units, err := s.UsageToday(ctx, user.ID, "transcribe")
	if err != nil {
		t.Fatalf("usage today: %v", err)
	}
	if units != 0 {
		t.Fatalf("usage still present: %v", units)
	}
	var events int
	if err := s.pool.QueryRow(ctx, `SELECT count(*) FROM revenuecat_events WHERE event_id IN ('evt-del', 'evt-alias')`).Scan(&events); err != nil {
		t.Fatalf("count events: %v", err)
	}
	if events != 0 {
		t.Fatalf("revenuecat events still present: %d", events)
	}

	// A second delete is a no-op, not an error.
	deleted, err = s.DeleteUser(ctx, user.ID)
	if err != nil {
		t.Fatalf("second delete: %v", err)
	}
	if deleted {
		t.Fatal("second delete should report nothing was removed")
	}
}
