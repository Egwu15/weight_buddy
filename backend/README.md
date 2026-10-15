# Weight Buddy backend

A small Go service that backs the Weight Buddy Flutter app: anonymous device
sign-in, RevenueCat entitlements, metered AI proxy and abuse protection. It is
a single static binary, configured purely from environment variables, with
`/healthz`, graceful shutdown and migrations run by a separate command.

## Layout

    cmd/api          the HTTP service
    cmd/migrate      applies the embedded SQL migrations
    internal/auth    JWT issue/verify (anonymous sign-in seam)
    internal/ai      provider interface + OpenAI implementation + prompts
    internal/http    router, middleware, handlers
    internal/store   pgx persistence (no ORM)
    internal/entitlements  RevenueCat webhook -> entitlement state
    internal/limits  daily quotas + global spend cap
    migrations       embedded goose SQL

## Endpoints (v1)

- `POST /v1/auth/anonymous` `{install_id}` -> `{token, user_id}`
- `POST /v1/auth/google` `{id_token, install_id}` -> `{token, user_id, linked}`;
  an anonymous `Authorization` session on the request is linked to the same
  account, so usage and any RevenueCat purchase stay attached
- `GET  /v1/me` -> user, entitlement, remaining limits, spend remaining
- `DELETE /v1/me` -> 204; deletes the account, its entitlement and usage, and
  its RevenueCat event records. Idempotent: a retry with the same token is 204
- `GET  /delete-account` -> public page explaining in-app deletion and the
  support-email fallback (Play requires this web link)
- `POST /v1/webhooks/revenuecat` — `Authorization` header checked in constant
  time; idempotent on the event id
- `POST /v1/ai/transcribe` (multipart `file`, optional `prompt`) -> `{text}`
- `POST /v1/ai/parse` (auto meal/workout), plus `/v1/ai/parse-meal` and
  `/v1/ai/parse-exercise`
- `POST /v1/ai/chat`, `/v1/ai/distill-memories`, `/v1/ai/extract-exercises`
- `GET  /healthz`

Every authenticated AI route: authenticate -> check entitlement -> check limits
and spend cap -> call the provider -> record usage -> respond.

## Running locally

    createdb weight_buddy
    export DATABASE_URL="postgres://user@localhost:5432/weight_buddy?sslmode=disable"
    export JWT_SECRET="dev-secret"
    export GOOGLE_WEB_CLIENT_ID="your-web-client.apps.googleusercontent.com"
    make migrate
    make run

The AI routes answer `503 not_configured` until `OPENAI_API_KEY` is set.

## Tests

    make test        # go test ./...
    make vet         # go vet ./...

Store integration tests run only when `TEST_DATABASE_URL` points at a scratch
database (they migrate it and truncate the tables); otherwise they skip:

    createdb weight_buddy_test
    TEST_DATABASE_URL="postgres://user@localhost:5432/weight_buddy_test?sslmode=disable" go test ./...

## Deploying (Contabo VPS)

One static binary behind Caddy on the same host as Postgres.

1. Build: `make build` (produces `bin/weight-buddy` and `bin/weight-buddy-migrate`).
2. Copy both binaries and `deploy/weight-buddy.service` to the host.
3. Create `/etc/weight-buddy/weight-buddy.env` from `.env.example` and
   `chmod 600` it.
4. `sudo systemctl enable --now weight-buddy` (migrations are applied by
   `ExecStartPre`, which runs the migrate binary with the same environment).
5. Put `deploy/Caddyfile` in `/etc/caddy/Caddyfile`, then
   `sudo systemctl reload caddy`.

`/healthz` is the readiness probe for a load balancer or Basecove.

## Configuration

Every variable is documented in `.env.example`. `DATABASE_URL`, `JWT_SECRET`,
`GOOGLE_WEB_CLIENT_ID` and `SUPPORT_EMAIL` are required; everything else has a
default. Limits and per-kind costs live in `internal/limits` (a Go struct), not
the database.
