package store

import (
	"context"
	"fmt"
)

// AdminStats is the read-only snapshot rendered by the /admin page. It holds
// aggregates only: no install ids, tokens or user text leave the database.
type AdminStats struct {
	UsersTotal         int64
	UsersGoogleLinked  int64
	UsersCreatedToday  int64
	UsersCreatedLast7  int64
	SignupsToday       int64
	SpendToday         float64
	WebhookEventsTotal int64
	WebhookEventsToday int64
	Entitlements       []AdminEntitlementCount
	UsageToday         []AdminUsageRow
}

// AdminEntitlementCount is one (entitlement, status) bucket.
type AdminEntitlementCount struct {
	Entitlement string
	Status      string
	Count       int64
}

// AdminUsageRow is today's usage for one kind.
type AdminUsageRow struct {
	Kind  string
	Calls int64
	Units float64
	Cost  float64
}

// AdminStats gathers the aggregates shown on the admin page. These are a
// handful of small queries on a low-traffic internal page, kept out of the
// request hot path.
func (s *Store) AdminStats(ctx context.Context) (AdminStats, error) {
	var out AdminStats

	const usersQuery = `
SELECT count(*),
       count(*) FILTER (WHERE google_sub IS NOT NULL),
       count(*) FILTER (WHERE created_at >= current_date),
       count(*) FILTER (WHERE created_at >= now() - interval '7 days')
FROM users`
	if err := s.pool.QueryRow(ctx, usersQuery).Scan(
		&out.UsersTotal,
		&out.UsersGoogleLinked,
		&out.UsersCreatedToday,
		&out.UsersCreatedLast7,
	); err != nil {
		return AdminStats{}, fmt.Errorf("admin users: %w", err)
	}

	const signupsQuery = `
SELECT COALESCE(SUM(count), 0) FROM device_signups WHERE day = current_date`
	if err := s.pool.QueryRow(ctx, signupsQuery).Scan(&out.SignupsToday); err != nil {
		return AdminStats{}, fmt.Errorf("admin signups: %w", err)
	}

	const spendQuery = `
SELECT COALESCE((SELECT cost_estimate FROM daily_spend WHERE day = current_date), 0)`
	if err := s.pool.QueryRow(ctx, spendQuery).Scan(&out.SpendToday); err != nil {
		return AdminStats{}, fmt.Errorf("admin spend: %w", err)
	}

	const eventsQuery = `
SELECT count(*), count(*) FILTER (WHERE received_at >= now() - interval '24 hours')
FROM revenuecat_events`
	if err := s.pool.QueryRow(ctx, eventsQuery).Scan(
		&out.WebhookEventsTotal,
		&out.WebhookEventsToday,
	); err != nil {
		return AdminStats{}, fmt.Errorf("admin webhook events: %w", err)
	}

	const entQuery = `
SELECT entitlement, status, count(*)
FROM entitlements
GROUP BY entitlement, status
ORDER BY entitlement, status`
	rows, err := s.pool.Query(ctx, entQuery)
	if err != nil {
		return AdminStats{}, fmt.Errorf("admin entitlements: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var row AdminEntitlementCount
		if err := rows.Scan(&row.Entitlement, &row.Status, &row.Count); err != nil {
			return AdminStats{}, fmt.Errorf("admin entitlements scan: %w", err)
		}
		out.Entitlements = append(out.Entitlements, row)
	}
	if err := rows.Err(); err != nil {
		return AdminStats{}, fmt.Errorf("admin entitlements rows: %w", err)
	}

	const usageQuery = `
SELECT kind, count(*), COALESCE(SUM(units), 0), COALESCE(SUM(cost_estimate), 0)
FROM usage
WHERE created_at >= current_date
GROUP BY kind
ORDER BY 4 DESC, kind`
	usageRows, err := s.pool.Query(ctx, usageQuery)
	if err != nil {
		return AdminStats{}, fmt.Errorf("admin usage: %w", err)
	}
	defer usageRows.Close()
	for usageRows.Next() {
		var row AdminUsageRow
		if err := usageRows.Scan(&row.Kind, &row.Calls, &row.Units, &row.Cost); err != nil {
			return AdminStats{}, fmt.Errorf("admin usage scan: %w", err)
		}
		out.UsageToday = append(out.UsageToday, row)
	}
	if err := usageRows.Err(); err != nil {
		return AdminStats{}, fmt.Errorf("admin usage rows: %w", err)
	}

	return out, nil
}
