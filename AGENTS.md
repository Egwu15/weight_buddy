# Backend Template Brief (Go)

Work through the TASKS section one task at a time. Do not start a task until the previous one builds and its checks pass.

## Context

Ted is shipping Flutter apps to the Google Play Store. Apps are free to download, with a subscription for higher limits (no BYOK). Each app gets its own small Go backend, started from this same template and then split into its own repo. Backends must be fully independent: no shared database, no shared keys, no shared code at runtime.

First app using this template: **Calorie tracker** (voice-first meal/exercise logging; audio -> transcription -> structured parse).
Second app: **Litpace** (reads PDF/Markdown aloud with word-level highlighting via a timestamped TTS API). Same template, different AI proxy endpoints.

Deployment: Contabo VPS, plain `systemd` service behind Caddy, Postgres on the same host. Keep it compatible with a later move to Basecove (Ted's deploy tool): one static binary, config via env vars, a `/healthz` endpoint, graceful shutdown, migrations run by a separate command.

## Stack (do not substitute)

- Go (latest stable), standard `net/http` + `chi` router
- Postgres via `pgx`, migrations with `goose`
- JWT (HS256 to start) for app sessions
- Config from environment variables only, validated at startup
- Structured logging with `log/slog`
- Tests with the standard `testing` package; table-driven where sensible

## Template responsibilities

1. **Auth**: anonymous device sign-in first (client sends a random install id, gets a user + JWT). Leave a clean seam to add Google sign-in later. Do not build Google sign-in now.
2. **Entitlements via RevenueCat**: a webhook receiver stores one entitlement row per user. The app uses our own user id as the RevenueCat app user id.
3. **Metered AI proxy**: app calls our backend; the backend calls the AI provider with our key, enforces per-user limits based on entitlement, and records usage.
4. **Abuse protection**: per-IP and per-user rate limits, a per-device cap on free-tier accounts, and a global daily spend cap that makes the proxy return a friendly 503 when hit.
5. **Ops**: `/healthz`, graceful shutdown, request ID logging.

## Data model (initial migration)

- `users(id uuid pk, install_id text unique, created_at)`
- `entitlements(user_id uuid pk references users, entitlement text, status text, expires_at timestamptz null, updated_at)`
  - status values: `active`, `grace`, `expired`, `cancelled_active` (cancelled but still within paid period)
- `revenuecat_events(event_id text pk, received_at, payload jsonb)` — used for idempotency
- `usage(id bigserial pk, user_id, kind text, units numeric, cost_estimate numeric, created_at)` with an index on `(user_id, created_at)`
- `daily_spend(day date pk, cost_estimate numeric)`

Limits live in config (env or a small YAML/Go struct), not in the database: free tier vs paid tier, per day, per `kind`.

## HTTP API (v1)

- `POST /v1/auth/anonymous` body `{install_id}` -> `{token, user_id}`
- `GET  /v1/me` -> user, entitlement, remaining limits for today
- `POST /v1/webhooks/revenuecat` — protected by a shared secret in the `Authorization` header (value from env `REVENUECAT_WEBHOOK_SECRET`, compared in constant time). Idempotent on event id. Handles purchase, renewal, cancellation, uncancellation, expiration, billing issue, product change, transfer. **Check the current RevenueCat webhook docs for exact event names and fields before coding; do not rely on memory.**
- `GET  /healthz`
- AI proxy endpoints are app-specific. For the calorie tracker:
  - `POST /v1/ai/transcribe` (audio upload -> text)
  - `POST /v1/ai/parse-meal` (text -> structured meal/macros JSON)
  - `POST /v1/ai/parse-exercise` (text -> structured exercise JSON)
  Each endpoint: authenticate -> check entitlement -> check limits -> call provider -> record usage -> respond.

## Rules for the agent

- Small, reviewable commits: one task = one commit.
- No new dependencies beyond the stack above without asking.
- Never log secrets, tokens, audio, or user text content.
- Every handler returns consistent JSON errors: `{"error": {"code": "...", "message": "..."}}`.
- Every external call (AI provider, RevenueCat REST) has a timeout and context cancellation.
- Add a test for each task. Run `go vet ./...` and `go test ./...` before declaring a task done.
- If a requirement is unclear, ask instead of guessing.

## Tasks (feed one at a time)

1. Scaffold: module layout (`cmd/api`, `cmd/migrate`, `internal/{config,http,auth,store,entitlements,ai,limits}`), config loading and validation, `/healthz`, graceful shutdown, slog setup.
2. Migrations for the data model above, plus a `cmd/migrate` command. Add a store layer with the queries needed (no ORM).
3. Anonymous auth: `POST /v1/auth/anonymous`, JWT issue/verify middleware, per-device free-account cap.
4. RevenueCat webhook: secret check, idempotent event storage, entitlement upsert logic, tests using sample payloads (copy real sample payloads from RevenueCat docs into test fixtures).
5. Entitlement refresh fallback: if a user's row is stale, fetch from RevenueCat REST API (key from env), with a short cache. Tests with a fake HTTP server.
6. Limits and usage: free vs paid daily limits per `kind`, usage recording, `GET /v1/me` showing remaining limits, global daily spend cap.
7. AI proxy for the tracker: the three endpoints above behind a small `Provider` interface so the AI vendor can be swapped. Include a fake provider for tests.
8. Rate limiting middleware (per-IP and per-user), request ID middleware, consistent error responses.
9. Deployment: systemd unit file, Caddyfile snippet, `.env.example`, a `Makefile` (build, test, migrate), and a short README with setup steps for the VPS.
10. Review pass: list anything unfinished, risky or untested. Do not fix anything in this task, only report.

## After the tracker ships

Copy the repo to a new one for Litpace. Keep auth, entitlements, limits and ops unchanged. Replace the tracker's AI endpoints with Litpace's (TTS with timestamp alignment, with caching of generated audio per document so repeat listens cost nothing). Do not edit the tracker repo while doing this.

## Repo layout note

This is a monorepo: the Flutter app lives in `mobile/` and the Go backend in `backend/`. Each backend is still destined to be split into its own repo later, so keep `backend/` self-contained.
