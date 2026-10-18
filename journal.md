# Decision Journal

Every significant decision, why it was made, and what would reverse it.

**Read this before changing the spec.** Some "obvious improvements" have already been considered and
rejected for a reason recorded here. If the reason no longer holds, supersede the entry — do not
silently contradict it.

**How to add an entry.** Newest first. Next `D-NNN`. Every entry needs a **Reverses if** line: the
observable condition that should make us change our mind.

**Statuses:** `Active` · `Superseded by D-NNN` · `Revisit at <phase/date>`

This journal begins on **2026-10-15**, when the embedded website and the mobile legal links landed.
Earlier choices — the Go stack, the `mobile/` + `backend/` monorepo split, the move from BYOK to a
backend-proxied AI key — predate it and are recorded only in `main.md` and the git history.

---

## D-023 — Force update is a server minimum, not a hardcoded client check

**2026-10-18 · Active**

The app compares its installed `versionName` with `minimum_version` from the public, uncached
`GET /v1/app/version` endpoint at launch and on resume. An older build gets a blocking screen with an
"Update now" button that opens the Play listing; there is no dismiss and no back path. The minimum lives
in `MIN_APP_VERSION` so an old build can be retired without shipping another build first, and the
default is `1.0.0` so the gate is inert until deliberately raised. The check fails open on timeout,
transport error or malformed JSON: an offline launch must still reach the local log, and a backend
outage must not lock every user out. The trade-off is that an attacker who blocks the endpoint can skip
the gate, which is acceptable for a client-side check whose real purpose is stopping stale API clients,
not enforcing security. Raise the minimum only after the replacement is at 100% rollout; a staged
rollout plus a raised floor would strand users who cannot yet download it. The response carries one Play
Store URL, so iOS needs a per-platform URL before it ships.

**Reverses if:** the app needs a soft "update available" prompt as well as a hard block, a platform other
than Android ships, or stale clients must be denied at the API layer rather than only in the UI.

**See:** `backend/internal/http/version.go`, `backend/internal/config/config.go`,
`mobile/lib/ui/update_gate.dart`, `mobile/lib/data/app_update.dart`, `mobile/store/listing.md`

---

## D-022 — Store listing leads with voice logging and discloses the free allowance

**2026-10-18 · Active**

The Play assets are a 1024x500 feature graphic and a paste-ready `mobile/store/listing.md`. The graphic
reuses the app's own identity (pot background, jollof/plantain waveform, mono wordmark) and shows one
worked example, "Jollof rice and chicken" to 612 kcal with macros, so the promise is visible without a
screenshot collage. The title is `Weight Buddy: Calorie Tracker` (29/30) to carry the search term the
product is bought on; the short description is 76/80. Copy stays plain, uses no em dashes and never
names the AI provider, matching the site and app. It states the log stays on the device and the server
keeps only account and usage metadata, and it discloses the free allowance (10 transcriptions, 20 coach
replies a day) because there is no purchasable paid tier yet. A paid-tier mention is deliberately absent
so the listing does not promise something the app cannot sell.

**Reverses if:** subscriptions go live (add tiers and pricing language), the backend free limits change
(update the allowance line), or the listing's install conversion shows the feature graphic or title
underperforming.

**See:** `mobile/store/feature-graphic-1024x500.png`, `mobile/store/listing.md`,
`backend/internal/limits/limits.go`

---

## D-021 — The operator page is opt-in, read-only and separate from the site

**2026-10-17 · Active**

`/admin` is a single server-rendered page in the Go binary, not part of the Vite site: no scripts, no
external assets, so it cannot break when the marketing site is rebuilt. It is registered only when
`ADMIN_TOKEN` is set (16+ characters, validated at startup); with the variable empty the route does not
exist, which makes "not configured" and "wrong URL" both a plain 404. Auth started as HTTP Basic and was
replaced the same day by a login page at `/admin/login` with a stateless signed session: an HMAC over
an expiry, keyed from `ADMIN_TOKEN`, so rotating the token invalidates every session. The cookie is
HttpOnly, SameSite=Strict, Path=/admin, lasts 12 hours and is Secure in production. Unauthenticated page
loads redirect to the form rather than sending a Basic challenge, so browsers never get the native
prompt; Basic auth is still accepted for scripts. No CSRF token was added: SameSite=Strict covers the
logout POST, and login CSRF is meaningless with one shared credential. The page shows aggregates only
(user counts,
Google links, today's signups, entitlement buckets, usage by kind, spend, webhook counts) so no install
ids, tokens or user text are exposed; entitlement write actions were deliberately excluded. "Cap
remaining" is derived from the same persisted spend total the page displays, not from the enforcer's
in-memory counter, which resets on restart.

**Reverses if:** support needs entitlement actions (then add them with an audit trail), or the page
grows into a real console with multiple operators (then replace Basic auth with SSO).

**See:** `backend/internal/http/admin.go`, `backend/internal/store/admin.go`,
`backend/internal/http/router.go`, `backend/.env.example`, `backend/README.md`

---

## D-020 — Google sign-in failed because only the Web OAuth client existed

**2026-10-17 · Active**

Symptom: the account chooser opens with the app name, the account is selected, then the sheet closes
and the plugin reports `GoogleSignInExceptionCode.canceled [16] Account reauth failed`, with no token
and no backend call. A cold reboot, a clean uninstall/reinstall, clearing the plugin session before
`authenticate()`, and the account itself were all ruled out. The actual cause: only a **Web** client had
been created; the **Android** client (package + signing SHA) did not exist. Google's "Account reauth
failed" text is misleading, but it is the standard symptom of a missing or mismatched Android client.
`VerifyCallerOperation` succeeding does not prove the Android client exists; it checks the app's
signing identity, not that the client is registered in the token audience's project. The fix is to
create an Android client in the same project (package `com.tedif.weight_buddy`, debug SHA, and a
separate client for the Play App Signing SHA) and allow propagation time (5 minutes to a few hours).
Clearing the plugin session before sign-in was kept: it is harmless and guards the documented
repeat-sign-in bug where a stale Credential Manager relationship forces the AccountReauth path.

**Resolved:** creating the Android client (package + debug SHA) fixed it. `POST /v1/auth/google`
returned 200, the existing anonymous user was linked in place (`google_sub` set), and a sign-out
followed by a second sign-in also returned 200, confirming the pre-sign-out hardening works. The Play
App Signing SHA still needs its own Android client before a store build can sign in.

**Reverses if:** Google starts returning a distinguishable error for a missing Android client, or the
app moves to `google-services.json`/Firebase registration.

**See:** `backend/internal/auth/google.go`, `mobile/lib/data/google_signin.dart`,
`mobile/lib/config.dart`, `HANDOFF.md` open item 6

---

## D-019 — Google's Web client is the token audience; the secret is never used

**2026-10-17 · Active**

Google sign-in is wired the "direct Google Cloud" way, with two clients: a **Web** client whose id is
the ID-token audience (set as `GOOGLE_WEB_CLIENT_ID` on the server and passed to the app at build time
via `--dart-define`, because it is compile-time config), and an **Android** client that authorises the
package plus signing SHA. The Web client's secret is not needed: the backend verifies the token against
Google's public keys and the expected audience, and no authorization code is exchanged anywhere. Mobile
clients cannot keep secrets anyway, and the Android client has none. Setup mistakes surface as a
`canceled` result from Credential Manager, which is why debug builds log the underlying exception code;
a real "canceled" and a misconfiguration are otherwise indistinguishable to the user.

**Reverses if:** we add a server-side authorization-code flow (then the secret stays on the server), or
switch to Firebase/`google-services.json` registration.

**See:** `backend/internal/auth/google.go`, `backend/internal/http/google.go`,
`mobile/lib/data/google_signin.dart`, `mobile/lib/config.dart`, `backend/docker-compose.yml`

---

## D-018 — The home page uses real captures; the store set is 9:16 at 1080x1920

**2026-10-17 · Active**

The three home-page placeholders were replaced with real screenshots, matching the section's own copy:
Today's wave, the month view and the weight trend. The site serves 540x960 copies from
`backend/web/public/screenshots/` inside the existing phone frames; the frames moved from 9:19 to 9:16
and lost the fake notch so the real status bar is not covered. The Play set stays in
`mobile/store/screenshots/` at 1080x1920, 24-bit PNG with no alpha (Play caps the long side at 2x the
short side, so the emulator's native 1080x2424 was out), with the coach shot Play-only. A 512x512 store
icon is generated from `assets/icon/app_icon.png`. A 1024x500 feature graphic is still needed.

**Reverses if:** the landing page gets a dedicated marketing layout (then the phone frames and copies
change together), or Play changes its screenshot limits.

**See:** `backend/web/src/pages/Home.tsx`, `backend/web/src/styles.css`,
`backend/web/public/screenshots/`, `mobile/store/`

---

## D-017 — The record sheet's "connect" prompt retries sign-in, with Settings as fallback

**2026-10-17 · Active**

The sheet shows its "Connect to Weight Buddy" state whenever there is no session, which in practice
means sign-in failed (usually offline at first launch) or a stored session was rejected. Its only
action used to be "Open Settings", which mismatched the copy ("check your network and try again") and
sent an offline user somewhere that cannot fix a dead connection. "Try again" is now the primary
button: it calls `SettingsController.refreshSession()` and, on failure, raises "Still no connection.
Check your network and try again." as a top toast (`AppToast`, the app's snackbar replacement) so the
prompt itself stays uncluttered. "Open Settings" stays as a secondary text button for the
rejected-session case (and for linking Google). Retry was chosen as the primary because the common
cause is connectivity, not a misconfigured account.

**Reverses if:** sign-in gains its own surfacing elsewhere (so the sheet can always assume a session),
or users are found to need account repair far more often than reconnection.

**See:** `mobile/lib/ui/record/record_sheet.dart`, `mobile/lib/providers/providers.dart`
(`SettingsController.refreshSession`), `mobile/test/widget_test.dart`

---

## D-016 — Frozen legal snapshots are write-once, and the first archive now exists

**2026-10-17 · Active**

`snapshot-legal.mjs` refuses to write a snapshot whose target already exists unless `FORCE=1` is set:
an archived page is the wording a user already accepted, so re-running for the same date must not
silently replace it. The "Previous versions" list is now one shared component
(`PreviousLegalVersions.tsx`, with `archiveHref`) instead of copy-pasted markup in the privacy policy
and the terms, and the archive route is documented as owned in two places (that component and the
script). The copy changes to privacy/terms were made correctly this time: the outgoing 2026-10-15
wording was frozen from a clean `git archive HEAD` build into `legal/archive/2026-10-15/`, then
`lastUpdated` and `kLegalVersion` moved to `2026-10-17` and the date was added to `config.legalArchive`.

**Reverses if:** legal pages move to a CMS or documentation platform that versions content for us, or a
frozen snapshot ever needs a legitimate correction (then `FORCE=1` plus a superseding note, not a
silent rewrite).

**See:** `backend/web/scripts/snapshot-legal.mjs`,
`backend/web/src/components/PreviousLegalVersions.tsx`, `backend/web/src/config.ts`,
`mobile/lib/config.dart`

---

## D-015 — The coach disclaimer is dismissable and the choice is remembered

**2026-10-17 · Active**

The "not a doctor" line under the coach is not a permanent fixture. It renders with a close button and
the dismissal is persisted as `coach_disclaimer_dismissed` in `app_settings` (via `AppSettingsData`),
so it does not reappear on later visits. A visible close was chosen over a timed fade or a one-per-
session hide because the user asked for control; the wording also moved off "The coach is an AI" to
plain phrasing. Keeping a permanent, undismissable banner was rejected as clutter on a screen the user
reads constantly.

**Reverses if:** legal review requires the disclaimer to be non-dismissable (then drop the control and
the setting), or app-store policy demands a fixed safety notice.

**See:** `mobile/lib/ui/coach/coach_screen.dart`, `mobile/lib/models/app_settings_data.dart`,
`mobile/lib/providers/providers.dart`

---

## D-014 — User-facing copy in the app drops em dashes and AI-ish phrasing

**2026-10-17 · Active**

The app's visible strings now match the site rule: no em dashes, and no phrasing that reads as
generated (clause-chaining dashes, "with AI" techy labels, hedgy over-explanation). Em dashes become
full stops, commas or colons; a lone "no value" placeholder uses an en dash instead. Scope is
user-visible strings only — code comments and dartdoc keep their em dashes. The coach system prompt is
unchanged. The demo seed's chat text was rewritten too, since it is shown to the user in the coach
demo.

**Reverses if:** the copy starts to read as choppy or under-explained, or a style guide is adopted that
permits em dashes.

**See:** `mobile/lib/ui/**`, `mobile/lib/data/ai_service.dart`,
`mobile/lib/utils/nudge_message.dart`, `mobile/lib/data/seed_demo.dart`,
`mobile/test/reminder_logic_test.dart`

---

## D-013 — Legal documents are versioned by frozen snapshots, and acceptance is recorded

**2026-10-17 · Active**

The privacy policy and terms are versioned by effective date. `make legal-snapshot` freezes the
outgoing pages into `web/public/legal/archive/<date>/` as self-contained HTML (CSS inlined, JavaScript
dropped), served read-only at `/legal/archive/<date>/<doc>/`; `config.legalArchive` links back to them
from the current pages, and `kLegalVersion` in the app is bumped with the site's `lastUpdated`. The app
records the accepted version plus a timestamp in secure storage when onboarding completes, so the
wording a user agreed to can be shown later. Git history alone was rejected: it is not a public,
citable record and cannot show what a given user actually saw.

**Reverses if:** the app gains real accounts with server-side consent records (then the accepted
version belongs with the account), or the site moves to a platform with built-in content versioning.

**See:** `backend/web/scripts/snapshot-legal.mjs`, `backend/web/src/config.ts`,
`mobile/lib/data/secure_settings.dart`, `mobile/lib/config.dart`

---

## D-012 — A Docker image and compose stack run the backend alongside systemd

**2026-10-17 · Active**

Added `backend/Dockerfile` (multi-stage: Node builds the site, Go builds both static binaries, a
distroless nonroot runtime holds only those binaries) and `backend/docker-compose.yml` (Postgres, a
one-shot `migrate` service, then the API), plus `make docker`/`docker-up`/`docker-down`/`docker-reset`.
The binary embeds the site and the migrations, so one image is self-contained, and the compose stack
reproduces the systemd migrate-then-serve ordering. `systemd` behind Caddy stays the primary Contabo
deployment; the container path is for running the whole backend, database included, with one command.

**Reverses if:** the container path goes unused and only duplicates the systemd path, or Basecove
standardises on a single run method.

**See:** `backend/Dockerfile`, `backend/docker-compose.yml`, `backend/Makefile`

---

## D-011 — The site's app text is filled; governing law is Nigeria

**2026-10-17 · Active**

The remaining `{{PLACEHOLDER}}` markers in `backend/web/src/config.ts` are filled. Governing law is set
to **the Federal Republic of Nigeria** because the publisher is established there — the server's
location (a Contabo VPS) does not decide governing law. The Play Store URL was corrected to the app's
real application id, `com.tedif.weight_buddy`. Both the Makefile `web` target and the Docker build now
run with `SITE_STRICT_PLACEHOLDERS=1`, so a marker left in the text fails the build instead of shipping.

**Reverses if:** the publisher is established elsewhere, or the qualified legal review (see §10)
advises a different clause.

**See:** `backend/web/src/config.ts`, `backend/Makefile`, `backend/Dockerfile`

---

## D-010 — Next steps live in `roadmap.md`, not the handoff

**2026-10-16 · Active**

Planned and outstanding work moved out of `HANDOFF.md` into `roadmap.md`, and the handoff now points
at it. Forward-looking lists grow every session and the handoff is meant to stay short and
disposable, so the roadmap is the one place "what next" lives.

**Reverses if:** the roadmap becomes a duplicate of `main.md` §10 rather than a sequence of work.

**See:** `roadmap.md`, `HANDOFF.md`

---

## D-009 — Documentation upkeep is a standing rule

**2026-10-16 · Active**

`HANDOFF.md` is rewritten at each session and kept to ~120 lines; `journal.md` is appended to,
newest first, each entry with a **Reverses if** line. The handoff is the first thing a fresh session
reads, and it only stays trustworthy if it is regenerated rather than edited. Durable content belongs
in `main.md`.

**Reverses if:** the handoff settles into a stale duplicate of `main.md`, or the ~120-line cap starts
forcing out facts that then get lost.

**See:** `HANDOFF.md` ("Maintaining these documents"), `AGENTS.md`

---

## D-008 — `main.md` moves to the repository root and covers the backend

**2026-10-16 · Active**

The spec began as the mobile-only Lean PRD at `mobile/docs/main.md`. The backend now implements
product behaviour, so it moved to the root and was rewritten to cover both. This corrected the
pre-backend claims: "Minimalist BYOK Architecture … zero cloud backend" is now the app signing into
the backend, which holds the AI key, enforces limits and meters spend.

**Reverses if:** the app and backend split into separate repositories, at which point each keeps its
own spec.

**See:** `main.md`

---

## D-007 — In-app legal links open the public pages

**2026-10-16 · Active**

Settings gained a **Legal & privacy** section (privacy policy, terms, account deletion) opened with
`url_launcher`. The URLs derive from `kSiteBaseUrl`, which defaults to `kBackendBaseUrl` because the
same Go binary serves the API and the site.

**Reverses if:** the site moves to its own domain — then set `--dart-define=SITE_BASE_URL`.

**See:** `mobile/lib/config.dart`, `mobile/lib/ui/settings/settings_screen.dart`

---

## D-006 — `make web` is a prerequisite of build/test/vet/run

**2026-10-15 · Active**

The Go build embeds `web/dist`, so the site must be built first or `//go:embed` fails. The `web`
target installs dependencies only when `node_modules` is absent, so it stays cheap on repeat runs,
which is what lets the other targets depend on it.

**Reverses if:** CI builds the site once up front and the per-target dependency makes the local loop
too slow.

**See:** `backend/Makefile`

---

## D-005 — The site handler caches file bytes and serves ETags

**2026-10-15 · Active**

Embedded files are read once into an in-memory cache and served through a `bytes.Reader` with a
stable `ETag`, so repeat requests do not re-copy large assets and revalidated HTML can answer `304`.

**Reverses if:** `web/dist` grows large enough that holding it in memory is a real cost.

**See:** `backend/internal/site/site.go`

---

## D-004 — Route mapping is generic, not a hard-coded list

**2026-10-15 · Active**

The server resolves an exact file first, otherwise `<path>/index.html`; the client derives its route
table from `NAV`; and a test walks every prerendered page and asserts it resolves. This removes the
hand-maintained server switch that could drift from the build.

**Reverses if:** a route needs behaviour that generic resolution cannot express.

**See:** `backend/internal/site/site.go`, `backend/web/src/routes.ts`, `backend/internal/site/site_test.go`

---

## D-003 — The website is the router's not-found fallback

**2026-10-15 · Active**

The site is mounted as chi's `NotFound`, so API routes always win and any path no API route claims
falls through to the site, which returns a real 404 page rather than an `index.html` fallback.

**Reverses if:** a route must be served by both the API and the site at the same path.

**See:** `backend/internal/http/router.go`

---

## D-002 — The backend keeps only `DELETE /v1/me`, not an HTML page

**2026-10-15 · Active**

The account-deletion page Google Play requires lives on the embedded site. The Go `/delete-account`
handler and the `SUPPORT_EMAIL` config were removed; the support address now lives in
`web/src/config.ts` with the rest of the app-specific text.

**Reverses if:** the site is ever served from a different host and the API needs a self-contained
page again.

**See:** `backend/internal/http/account.go`, `backend/web/src/config.ts`

---

## D-001 — The public site is a pre-rendered, embedded React app

**2026-10-15 · Active**

Home, privacy, terms and account-deletion pages are a Vite + React + TypeScript project under
`backend/web`, pre-rendered to static HTML (readable with JavaScript disabled), embedded into the Go
binary with `go:embed`, and served by the same server as the API. All app-specific text lives in
`web/src/config.ts` so the template can be copied to the next app by editing one file.

**Reverses if:** a simpler static site or a separate static host is preferred later.

**See:** `backend/web/`, `backend/webassets.go`, `backend/internal/site/`
