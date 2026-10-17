# Weight Buddy — Handoff

> State as of **2026-10-17**. Disposable by design: rewritten at each handoff and kept to ~120 lines.
> Anything durable belongs in `main.md` (what it is) or `journal.md` (why). If this file and `main.md`
> disagree, `main.md` wins — then fix this file.

## What this is

A voice-first calorie, macro and exercise tracker. A Flutter app (`mobile/`) plus a Go backend
(`backend/`): the app logs by voice or typing, the backend proxies the AI with a server-held key and
meters it. Free to download, with an optional subscription that raises the AI limits. 13+.

The log lives **on the device**. The server holds only an account id, subscription entitlement and
usage metadata (counts/costs) — never meal, workout, weigh-in or chat content.

## Read in this order

1. **`main.md`** — product + system source of truth (features, backend, data model, open items).
2. **`journal.md`** — every significant decision, newest first, each with a **Reverses if** line.
3. **`roadmap.md`** — planned and outstanding work, in rough order.
4. **`AGENTS.md`** — the backend build rules.

## Repository state

| | |
|---|---|
| Branch | `main`; **uncommitted work** in the tree (see below) |
| Recent | `2dc2e88` docs: move main.md to root · `e1db894` mobile legal links · `b4df8c0` embedded React site |
| Go | 80 tests pass, 11 skip (store integration needs `TEST_DATABASE_URL`) |
| Mobile | 159 tests pass; `flutter analyze` clean |
| Website | built by `make web` (strict placeholders), embedded via `//go:embed all:web/dist` |

Uncommitted: the site text is filled in `backend/web/src/config.ts` (governing law = Nigeria), and a
new Docker image + compose stack (`backend/Dockerfile`, `backend/docker-compose.yml`,
`backend/.dockerignore`, Makefile targets). The doc system (`HANDOFF.md`, `journal.md`, `roadmap.md`)
is also new and untracked. Nothing above is committed yet.

```sh
cd backend && make test      # strict site build, then go test ./...
cd backend && make vet       # strict site build, then go vet ./...
cd mobile  && flutter test
cd mobile  && flutter analyze

# whole backend (Postgres + migrate + api) in containers:
cd backend && cp .env.example .env    # sets the required JWT_SECRET
cd backend && make docker-up          # API on http://localhost:8080

# store integration tests (skipped without this):
createdb weight_buddy_test
TEST_DATABASE_URL="postgres://user@localhost:5432/weight_buddy_test?sslmode=disable" \
  go test ./backend/...
```

## What is built

- **App (`mobile/`):** voice + typed logging, meal macros, deterministic exercise burn, daily
  dashboard (Day's Wave), month calendar + streaks, weight tracking, coach chat with an on-device
  memory layer, saved exercise library, daily reminders, first-run onboarding, and Settings
  (Account & voice, Targets & profile, Daily reminder, Data, Legal & privacy links).
- **Backend (`backend/`):** anonymous + Google sign-in, RevenueCat webhook entitlements, metered AI
  proxy (transcribe / parse / chat / memories / exercise extract), per-kind daily limits, global
  spend cap, per-IP/user rate limits, per-device free-account cap, an embedded public website
  (home, privacy, terms, account deletion), `/healthz`, graceful shutdown, request-id logging.
- **Ops:** systemd + Caddy (primary VPS path), and a multi-stage Docker image with a compose stack
  (Postgres, one-shot migrate, API) as an alternative.

## Open (details in `main.md` §10)

1. Subscription is modelled in the backend but **not purchasable** — the app's RevenueCat seam is a
   no-op and no purchase SDK ships.
2. Legal copy: placeholders are filled (governing law = Nigeria), but privacy/terms/deletion are still
   a **draft needing a qualified review** before publishing, and their URLs feed the Play listing.
3. RevenueCat REST entitlement-refresh fallback (backend template task 5) not implemented.
4. `TRANSFER` webhook events are recorded but not applied.
5. Store SQL tests skip without `TEST_DATABASE_URL`; there is no CI.
6. The real Google token-verifier path is untested (tests inject a fake).
7. Rate limiting and the spend cap are process-local (single instance).
8. Dead code: `Store.Pool()`, and `CreateOrGetUser`/`UpsertEntitlement` (test-only).
9. Home-page screenshots are placeholders.

## Next

See **`roadmap.md`** — planned and outstanding work is kept there so this file stays short.

## Traps

- The Go build embeds `web/dist`; without `make web` it fails at `//go:embed`. `build/test/vet/run`
  depend on `web`, so use those targets.
- `make web` and the Docker build run with `SITE_STRICT_PLACEHOLDERS=1`: a leftover `{{...}}` in
  `web/src/config.ts` fails the build instead of shipping.
- The website is mounted as chi's `NotFound` so API routes always win; an unknown path is a real 404
  (never an `index.html` fallback).
- Never log content, tokens, audio or user text; the server stores metadata only.
- One AI provider key on the server — there is no BYOK.
- Docker: compose **requires `JWT_SECRET`** (`cp .env.example .env` sets it) and does not publish the
  DB port — the host already runs Postgres on 5432. Base images are pinned by digest.

## Maintaining these documents

- **Rewrite this file at each handoff**, ≤120 lines (a little over only when it earns it).
- **Append decisions to `journal.md`** — newest first, next `D-NNN`, each with a **Reverses if** line.
- Durable content goes in `main.md`, not here.
