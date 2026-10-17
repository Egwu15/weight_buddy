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
