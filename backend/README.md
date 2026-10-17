# Weight Buddy backend

A small Go service that backs the Weight Buddy Flutter app: anonymous device
sign-in, RevenueCat entitlements, metered AI proxy and abuse protection, plus
the public website (home, privacy policy, terms of service, account deletion).
It is a single static binary, configured purely from environment variables,
with `/healthz`, graceful shutdown and migrations run by a separate command.

## Layout

    cmd/api                the HTTP service
    cmd/migrate            applies the embedded SQL migrations
    internal/auth          JWT issue/verify (anonymous sign-in seam)
    internal/ai            provider interface + OpenAI implementation + prompts
    internal/http          router, middleware, handlers
    internal/site          serves the embedded public site
    internal/store         pgx persistence (no ORM)
    internal/entitlements  RevenueCat webhook -> entitlement state
    internal/limits        daily quotas + global spend cap
    migrations             embedded goose SQL
    web                    Vite + React + TypeScript public site (pre-rendered)
    webassets.go           embeds web/dist into the binary

## Endpoints (v1)

- `POST /v1/auth/anonymous` `{install_id}` -> `{token, user_id}`
- `POST /v1/auth/google` `{id_token, install_id}` -> `{token, user_id, linked}`;
  an anonymous `Authorization` session on the request is linked to the same
  account, so usage and any RevenueCat purchase stay attached
- `GET  /v1/me` -> user, entitlement, remaining limits, spend remaining
- `DELETE /v1/me` -> 204; deletes the account, its entitlement and usage, and
  its RevenueCat event records. Idempotent: a retry with the same token is 204
- `POST /v1/webhooks/revenuecat` — `Authorization` header checked in constant
  time; idempotent on the event id
- `POST /v1/ai/transcribe` (multipart `file`, optional `prompt`) -> `{text}`
- `POST /v1/ai/parse` (auto meal/workout), plus `/v1/ai/parse-meal` and
  `/v1/ai/parse-exercise`
- `POST /v1/ai/chat`, `/v1/ai/distill-memories`, `/v1/ai/extract-exercises`
- `GET  /healthz`

Every authenticated AI route: authenticate -> check entitlement -> check limits
and spend cap -> call the provider -> record usage -> respond.

## Public site

The same binary serves the marketing and legal pages at `/`, `/privacy`,
`/terms` and `/delete-account`. API routes always win; anything else falls
through to the site, which serves exact file matches only and answers unknown
paths with a real HTML 404 (never an index.html fallback).

All app-specific text lives in one file, `web/src/config.ts`, so the template
can be copied to another app by editing that file. The pages are pre-rendered
to static HTML at build time, so they read correctly with JavaScript disabled;
the client bundle only hydrates.

## Running locally

    createdb weight_buddy
    export DATABASE_URL="postgres://user@localhost:5432/weight_buddy?sslmode=disable"
    export JWT_SECRET="dev-secret"
    export GOOGLE_WEB_CLIENT_ID="your-web-client.apps.googleusercontent.com"
    make web     # build the embedded site first
    make migrate
    make run

The AI routes answer `503 not_configured` until `OPENAI_API_KEY` is set.

## Tests

    make test        # builds the embedded site, then go test ./...
    make vet         # builds the embedded site, then go vet ./...

Both targets build the site first because the Go build embeds `web/dist`. To run
the Go commands directly, run `make web` first; without `web/dist` the build
fails clearly at `//go:embed`.

Store integration tests run only when `TEST_DATABASE_URL` points at a scratch
database (they migrate it and truncate the tables); otherwise they skip:

    createdb weight_buddy_test
    TEST_DATABASE_URL="postgres://user@localhost:5432/weight_buddy_test?sslmode=disable" go test ./...

## Deploying (Contabo VPS)

One static binary behind Caddy on the same host as Postgres.

1. Build: `make build` (builds the site, then produces `bin/weight-buddy` and
   `bin/weight-buddy-migrate`).
2. Copy both binaries and `deploy/weight-buddy.service` to the host.
3. Create `/etc/weight-buddy/weight-buddy.env` from `.env.example` and
   `chmod 600` it. Fill in the required values (`DATABASE_URL`, `JWT_SECRET`,
   `GOOGLE_WEB_CLIENT_ID`) **before** restarting: config is validated at
   startup, so a missing variable crash-loops the service until the file is
   fixed.
4. `sudo systemctl enable --now weight-buddy` (migrations are applied by
   `ExecStartPre`, which runs the migrate binary with the same environment,
   before the new binary serves any request).
5. Put `deploy/Caddyfile` in `/etc/caddy/Caddyfile`, then
   `sudo systemctl reload caddy`.

`/healthz` is the readiness probe for a load balancer or Basecove.

## Docker

There is also a container image and a compose stack, for running the whole
backend (Postgres, migrations, API) with one command:

    cp .env.example .env     # fill in the required values
    docker compose up --build

The `Dockerfile` is multi-stage: it builds the site and both static binaries
(in which the site and migrations are embedded) and ships a distroless runtime
holding only those binaries, so the host needs no Go, Node or shell. The stack
mirrors the systemd flow — a one-shot `migrate` service runs before `api`
starts. `make docker`, `make docker-up` and `make docker-down` wrap these.
For the Contabo VPS the systemd unit above is still the primary path.

## Configuration

Every variable is documented in `.env.example`. `DATABASE_URL`, `JWT_SECRET`
and `GOOGLE_WEB_CLIENT_ID` are required; everything else has a default. Limits
and per-kind costs live in `internal/limits` (a Go struct), not the database.
The public site's text and links live in `web/src/config.ts`, not in the
environment.

Fill in the `{{...}}` placeholders in `web/src/config.ts` before publishing. The
site build prints a warning listing any that remain and, when
`SITE_STRICT_PLACEHOLDERS=1` is set, fails instead of emitting them.
