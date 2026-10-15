-- +goose Up
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    install_id text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE entitlements (
    user_id     uuid PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    entitlement text NOT NULL,
    status      text NOT NULL CHECK (status IN ('active', 'grace', 'expired', 'cancelled_active')),
    expires_at  timestamptz,
    updated_at  timestamptz NOT NULL DEFAULT now()
);

-- One row per RevenueCat event, used for idempotent webhook handling.
CREATE TABLE revenuecat_events (
    event_id    text PRIMARY KEY,
    received_at timestamptz NOT NULL DEFAULT now(),
    payload     jsonb NOT NULL
);

CREATE TABLE usage (
    id            bigserial PRIMARY KEY,
    user_id       uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    kind          text NOT NULL,
    units         numeric NOT NULL DEFAULT 0,
    cost_estimate numeric NOT NULL DEFAULT 0,
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX usage_user_created_idx ON usage (user_id, created_at);

CREATE TABLE daily_spend (
    day           date PRIMARY KEY,
    cost_estimate numeric NOT NULL DEFAULT 0
);

-- Abuse protection: how many free accounts a single device (identified by a
-- hashed client IP) has created on a given day, so one client cannot farm
-- unlimited anonymous accounts.
CREATE TABLE device_signups (
    ip_hash text NOT NULL,
    day     date NOT NULL,
    count   integer NOT NULL DEFAULT 0,
    PRIMARY KEY (ip_hash, day)
);

-- +goose Down
DROP TABLE device_signups;
DROP TABLE daily_spend;
DROP TABLE usage;
DROP TABLE revenuecat_events;
DROP TABLE entitlements;
DROP TABLE users;
