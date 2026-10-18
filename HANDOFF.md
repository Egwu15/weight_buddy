# Weight Buddy — Handoff

> State as of **2026-10-18**. Disposable by design: rewritten at each handoff and kept to ~120 lines.
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
| Recent | `276d140` docs update · `8aae628` Docker image + compose · `91ca8fe` site text + Play id |
| Go | 94 tests pass, 11 skip (store integration needs `TEST_DATABASE_URL`) |
| Mobile | 183 tests pass; `flutter analyze` clean |
| Website | pre-rendered by `make web`, embedded via `//go:embed all:web/dist` |

Uncommitted: site copy, coach disclaimer, legal versioning, app copy pass, the Play pack in
`mobile/store/` (icon, screenshots, feature graphic, Play-ordered `listing.md`), the force-update
gate (app 1.0.5+5, `GET /v1/app/version`), and the compose stack now using `DATABASE_URL` instead
of its own Postgres container/volume (D-025). Nothing above is committed yet.

```sh
cd backend && make test      # strict site build, then go test ./...
cd backend && make vet       # strict site build, then go vet ./...
cd mobile  && flutter test
cd mobile  && flutter analyze

cd backend && cp .env.example .env    # sets the required JWT_SECRET
cd backend && make docker-up           # migrate + API in containers, DB from DATABASE_URL

# store integration tests (skipped without this):
createdb weight_buddy_test
TEST_DATABASE_URL="postgres://user@localhost:5432/weight_buddy_test?sslmode=disable" \
  go test ./backend/...
```

## What is built

- **App (`mobile/`):** voice + typed logging, meal macros, deterministic exercise burn, Day's Wave,
  month calendar + streaks, weight tracking, coach chat with an on-device memory layer (dismissable
  "not a doctor" disclaimer), saved exercises, reminders, onboarding (records legal acceptance),
  Settings, and a launch/resume force-update gate that fails open when offline.
- **Store pack:** four 1080x1920 (9:16) screenshots, a 512x512 RGBA icon and the 1024x500 feature
  graphic in `mobile/store/`, plus `listing.md` in Play Console order (listing, settings, content
  ratings, target audience, data safety, health declarations, pricing, release, force update). The
  site uses 540x960 copies of three screenshots.
- **Backend (`backend/`):** anonymous + Google sign-in, RevenueCat webhook entitlements, metered AI
  proxy, per-kind daily limits, global spend cap, per-IP/user rate limits, per-device free-account
  cap, embedded website (home, privacy, terms, deletion), an opt-in read-only `/admin`, `/healthz`,
  graceful shutdown, request ids, and the public force-update endpoint.
- **Legal versioning:** effective-dated, frozen snapshots under `web/public/legal/archive/<date>/`
  (made with `make legal-snapshot`), linked via `config.legalArchive`; the app records acceptance and
  `2026-10-15` is frozen. Nothing reads the recorded acceptance back yet.
- **Ops:** systemd + Caddy (primary VPS path) and a multi-stage Docker image with a compose stack.

## Open (details in `main.md` §10)

1. Subscription is modelled in the backend but **not purchasable** — the app's RevenueCat seam is a
   no-op and no purchase SDK ships.
2. Legal copy is reviewed and versioned; Play Console still needs the published privacy, terms and
   deletion URLs.
3. RevenueCat REST entitlement-refresh fallback (backend template task 5) not implemented.
4. `TRANSFER` webhook events are recorded but not applied.
5. Store SQL tests skip without `TEST_DATABASE_URL`; there is no CI.
6. Google sign-in works end to end (debug Android client, `/v1/auth/google` 200, in-place link,
   repeat sign-in). The **Play App Signing** SHA-1 is registered for release builds.
7. Rate limiting and the spend cap are process-local (single instance).
8. Dead code: `Store.Pool()`, and `CreateOrGetUser`/`UpsertEntitlement` (test-only).
9. Seed weigh-ins span 28 days, so Today says "first reading"; Play assets in `mobile/store/` still
   need uploading.

## Traps

- The Go build embeds `web/dist`; without `make web` it fails at `//go:embed`. `build/test/vet/run`
  depend on `web`, so use those targets.
- `make web` and the Docker build run with `SITE_STRICT_PLACEHOLDERS=1`: a leftover `{{...}}` in
  `web/src/config.ts` fails the build instead of shipping.
- **Legal copy:** run `make legal-snapshot` *before* editing privacy/terms, then bump `config.ts`
  `lastUpdated`, `mobile/lib/config.dart` `kLegalVersion` and `config.legalArchive`. Never edit
  `web/public/legal/archive/`; re-running a date is refused unless `FORCE=1`.
- The website is mounted as chi's `NotFound` so API routes always win; an unknown path is a real 404
  (never an `index.html` fallback).
- Never log content, tokens, audio or user text; the server stores metadata only.
- One AI provider key on the server — there is no BYOK. Do not name the AI vendor in customer-facing
  copy.
- **Copy style (site and app):** no em dashes in user-visible strings, no AI-ish/robotic phrasing.
- Demo data is a debug-only feature (`Settings → Data → Load demo data`, gated by `kDebugMode`); it is
  not part of a release build.
- `/admin` exists only when `ADMIN_TOKEN` (16+ chars) is set. Sign in at `/admin/login` (user `admin`,
  password the token); a 12h signed cookie keeps you in, and Basic auth still works for scripts. It is
  read-only aggregates and never shows identifiers, tokens or user text.
- Docker: compose **requires `DATABASE_URL` and `JWT_SECRET`** and uses the
  Postgres at that URL (no database container or volume). From a container,
  use `host.docker.internal` instead of `localhost` when the DB is on the host.
  Base images are pinned by digest. No `# syntax=` directive on purpose (D-024):
  pulling the external frontend broke builds with "no active sessions".
- Google sign-in needs the **Web** client id on the server (audience) and at build time
  (`--dart-define=GOOGLE_WEB_CLIENT_ID=…`). The Android client (package + SHA) has no secret. Setup
  mistakes surface as `canceled`; debug builds log the real code in `google_signin.dart`.
- **Force update:** raise `MIN_APP_VERSION` only after that build is at 100% rollout, or users who
  cannot download it are locked out. The check fails open, so an outage never blocks logging.

## Maintaining these documents

- **Rewrite this file at each handoff**, ≤120 lines (a little over only when it earns it).
- **Append decisions to `journal.md`** — newest first, next `D-NNN`, each with a **Reverses if** line.
- Durable content goes in `main.md`, not here.
