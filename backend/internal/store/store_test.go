package store

import (
	"context"
	"database/sql"
	"errors"
	"os"
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

func TestRegisterSignupHonoursCap(t *testing.T) {
	s := testStore(t)
	ctx := context.Background()

	for i := 1; i <= 2; i++ {
		ok, err := s.RegisterSignup(ctx, "hash-a", 2)
		if err != nil {
			t.Fatalf("signup %d: %v", i, err)
		}
		if !ok {
			t.Fatalf("signup %d should be within cap 2", i)
		}
	}
	ok, err := s.RegisterSignup(ctx, "hash-a", 2)
	if err != nil {
		t.Fatalf("signup: %v", err)
	}
	if ok {
		t.Fatal("third signup should exceed cap 2")
	}

	// A different device has its own counter.
	ok, err = s.RegisterSignup(ctx, "hash-b", 2)
	if err != nil {
		t.Fatalf("signup other device: %v", err)
	}
	if !ok {
		t.Fatal("a fresh device should be within its own cap")
	}
}
