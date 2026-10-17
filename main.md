# Weight Buddy — Product & System Reference

> **Status:** Implemented as a Flutter app (`mobile/`) plus a Go backend (`backend/`). This document is the source of truth for what was built; features marked **Built** are implemented and tested. Known gaps and draft areas are listed in §10.
>
> This began as the mobile app's Lean PRD and now covers the backend too, so it lives at the repository root.

## 1. Product Overview

A voice-first calorie, macro and exercise tracker. You log a meal or a workout by
speaking — or by typing when the room is noisy — and get back calories, macros or
a computed burn. To handle local and regional dish names that on-device speech
recognisers mishear, recorded audio is transcribed by an AI provider and the
transcript is parsed into structured entries.

The app is free to download, with an optional subscription that raises the AI
limits. There is no "bring your own key": the app signs in to the Weight Buddy
backend, and the backend calls the AI provider with our key and enforces the
limits.

Two things are deliberately separated:

- **Your log lives on your device.** Meals, workouts, weigh-ins, coach chat,
  memories and saved exercises are stored locally in SQLite; they are never
  uploaded as a log.
- **The server holds only what it needs to run the account** — an account
  identifier, subscription entitlement, and usage metadata (counts and estimated
  cost). It does not store the content of what you said or ask.

### Goals

- **Frictionless voice logging:** eliminate manual database searching through
  natural spoken input.
- **High transcription accuracy for local foods:** use an AI provider's
  speech-to-text instead of native device engines, with a custom vocabulary of
  local dish names.
- **Macronutrient tracking:** estimate daily protein, carbohydrate and fat totals
  alongside calories.
- **Metered, abuse-protected AI:** run the AI through our backend so the provider
  key stays on the server, limits are enforced per user, and spend is capped.

## 2. Target User & Use Case

- **Primary user:** someone tracking their own nutrition and exercise.
- **Age:** 13 and over. The app and site are not directed at children under 13.
- **Core scenario:** the user taps record and speaks what they ate (including
  regional dishes) or how they moved — or types it instead — and gets an instant
  breakdown they can confirm, edit and save.

## 3. Repository Layout

This is a monorepo:

- `mobile/` — the Flutter app (iOS and Android).
- `backend/` — the Go service: API, metered AI proxy, entitlements, abuse
  protection, and the embedded public website. It is **self-contained** and
  destined to be split into its own repository. The same backend template is
  reused for the second app (Litpace), which replaces only the AI endpoints.
- `main.md` — this document.
- `AGENTS.md` — the backend template brief and build rules.

## 4. Core Functional Requirements (App)

### Feature 1: Device account, sign-in & custom vocabulary

**Status:** Built.

**Description:** Settings → **Account & voice** shows the signed-in session, today's
AI allowance and the transcription vocabulary. There is no API key on the device;
the provider key lives on the backend.

**Requirements:**

- **Anonymous device sign-in:** on first run the app generates a random install
  id, sends it to `POST /v1/auth/anonymous` and stores the returned session JWT
  and user id in the platform secure store (`flutter_secure_storage`). A returning
  device reuses its install id so it keeps the same account.
- **Optional Google sign-in:** with a Google ID token the app calls
  `POST /v1/auth/google`. The backend verifies the token against our OAuth web
  client id and stores only the account's stable identifier (`sub`) — never the
  email, name or photo. An existing anonymous session is linked to the same
  account so usage history and any purchase stay attached.
- **Session status & today's allowance:** the Account & voice screen shows whether
  the device is connected and, from `GET /v1/me`, the remaining allowance for each
  AI feature today.
- **Custom vocabulary:** an optional comma-separated list of local dish names
  (e.g. "Jollof, Egusi, Amala, Suya, Akara, Dodo"). The list is stored on the
  device and sent as the transcription `prompt` so regional foods are heard
  correctly.
- **Deletion:** a "Delete account" action in the Danger zone deletes the
  server-side account (with an option to also erase the on-device data).

### Feature 2: Voice Meal Logging & Macro Calculation

**Status:** Built.

**Description:** Convert recorded speech (or typed text) into structured food records including calories, macronutrients and a meal-type label.

**Requirements:**

- **Audio capture & transcription:** record raw audio on-device (e.g. .m4a or
  .wav) and send it to `POST /v1/ai/transcribe`, which proxies it to the AI
  provider's transcription model and returns the text. In production the audio
  goes to *our* server, not straight to the provider from the device.
- **Typing fallback:** the record sheet's idle view offers **"Type instead"** — a
  multiline field runs the same parse pipeline as voice (skipping transcription),
  so logging still works in noisy places or when the mic is unavailable.
- **Not-connected onboarding:** when the device has no session, the sheet explains
  what's needed and offers **"Go to Settings"**, which closes the sheet and jumps
  to Settings.
- **Structured parse:** the transcript text is sent to `POST /v1/ai/parse-meal`
  (or the auto-detecting `POST /v1/ai/parse`) and returned as strict JSON.
- **Extracted attributes:**
  - Food items with estimated portion sizes
  - Calories (kcal)
  - Protein (g)
  - Carbohydrates (g)
  - Fat (g)
  - Meal-type classification (breakfast / lunch / dinner / snack), inferred from
    the food and the device's local time, user-adjustable on the confirm card
- Display a confirmation card showing the parsed items, macro breakdown and a meal-type picker before persisting to local logs.

### Feature 3: Voice Exercise Logging & Burn Calculation

**Status:** Built.

**Description:** Convert recorded speech (or typed text) describing physical activity into calorie burn estimates.

**Requirements:**

- Transcribe recorded audio via `POST /v1/ai/transcribe`.
- Send the transcript to `POST /v1/ai/parse-exercise` to extract the workout's
  *structure* (activity name, sets, reps, duration) — never a calorie guess.
  Every burn is computed locally by the deterministic exercise engine (mechanical
  work for reps, MET for duration), priced off the user's latest weigh-in, so a
  45-second set can never log a workout-sized number.
- Append confirmed activity to the daily workout log.

### Feature 4: Daily Dashboard (Calories & Macros)

**Status:** Built.

**Description:** Single-screen view displaying daily progress and raw activity logs.

**Requirements:**

- **Calorie Summary Card:** Total Calories Consumed, Total Calories Burned, Net Calories, and **Left** — maintenance minus net (green when the day is still under budget, jollof when over).
- **Period glance:** under the daily ledger, a compact readout of what's left for the current **week** and **month** — the budget runs from today to the period's end, so a late sign-in or skipped days never inflate the number — tappable through to the Month tab for the full period view.
- **Macro Summary Card:** Daily totals for Protein (g), Carbohydrates (g), and Fat (g).
- **Day's Wave (signature):** Today's entries are drawn as a waveform — each peak is one entry, height follows calories, colour follows type (meal / exercise), position follows time of day. Tapping a peak reveals its summary; an empty day is a flatline invitation to log.
- **Log Timeline:** Chronological feed of meals (with macro details) and workouts logged for the active date.
- Delete/remove capability for individual log entries.
- **Edit & resend:** every timeline entry (and the details sheet) opens an editor — correct the words and **re-parse with AI**, or fix by hand (quantities scale calories/macros; add or remove items; meal type). Saving updates the row **in place** (same id and timestamp), so the timeline position and the day's maintenance snapshot stay intact — the fix for a wrong AI measurement or a forgotten item without re-dictating from scratch. At the confirm stage a **“fix the words”** action returns to the typing view pre-filled instead of discarding.

### Feature 5: Month Calendar, Maintenance Colors & Streaks

**Status:** Built.

**Description:** A month-at-a-glance calendar that tints every day by its balance against the maintenance-calorie target, with consecutive-day streaks up top.

**Requirements:**

- **Maintenance target setting:** user-configurable daily maintenance calories (Settings → Targets & profile), the line everything measures against.
- **Color coding:** a day with logs is tinted **ugu (green)** when net kcal ≤ maintenance, **jollof (red-orange)** when above, and stays neutral when nothing was logged.
- **Per-day maintenance snapshots:** every log records the maintenance target in effect that day (`day_maintenance`); the calendar and the ON-PLAN streak judge each day by its own snapshot (falling back to the current target for legacy days).
- **Streaks:** LOG STREAK (consecutive days with ≥1 entry) and ON-PLAN (consecutive days logged *and* at/below maintenance), computed from the last 90 days.
- **Week & month budget summaries:** two ledger cards above the calendar. The month card follows the existing month navigation; the week card (Monday–Sunday) has its own prev/next arrows. For the **ongoing period** the budget runs from **today → period end** at each day's maintenance target (per-day snapshot, falling back to the current target for days never logged); **LEFT** = budget − net − any overspend carried in from tracked days earlier in the period. **Untracked days count for nothing** — a late sign-in or skipped days never inflate LEFT, and under-eating never banks extra allowance (the card shows a `· TODAY →` marker and a "carries X over" footnote when relevant). Past periods keep the full-period ledger for review; future periods show the whole period's budget.
- **Navigation:** tapping a calendar day jumps the Today dashboard to that day.
- **Weight unit (kg/lb):** a per-entry input choice on the weigh-in sheet — readings are always stored and displayed in kg, so there is no global unit setting and nothing to configure on the Targets & profile page.

### Feature 6: Weight Tracking

**Status:** Built.

**Description:** Log weigh-ins at any rhythm (monthly is fine) and watch the trend.

**Requirements:**

- **Weight card on Today:** latest weight, the 30-day delta, and a hairline trend sparkline (custom-painted, matching the Day's Wave aesthetic).
- **Weigh-in sheet:** date, weight in kg or lb, optional note.
- **History screen:** full list newest-first with delete, plus a FAB to add.
- **Persistence:** dedicated `weigh_ins` table; the wipe includes weigh-ins.

### Feature 7: Coach Chat with Memory

**Status:** Built.

**Description:** A persistent chat that is fed a digest of the user's live data plus a distilled, editable memory layer. Replies come from `POST /v1/ai/chat`.

**Requirements:**

- **Context digest** assembled on the device per message: maintenance target, today's totals, last 7 days, weight trend, streaks, active memories, saved exercises.
- **Chat thread persisted locally** (`chat_messages`); one conversation with a "new conversation" reset (memories/exercises survive resets).
- **Memory layer:** every ~4 exchanges a strict-schema call to `POST /v1/ai/distill-memories` distils `{topic, content, category, action: create|update|remove}` facts; upsert is latest-wins per topic; stale facts can be retired by the model.
- **Memory manager screen:** view/edit/add/delete memories, source label (you said / coach learned), and a master **"Let the coach remember"** switch that stops both writes and injection.
- **Privacy:** memories live only on-device and travel to our backend (and on to the AI provider) solely as chat context, matching the rest of the coach.

### Feature 8: Auto-Saved Exercise Recommendations

**Status:** Built.

**Description:** When the coach gives exercise advice, a strict-schema extraction call (`POST /v1/ai/extract-exercises`) pulls the concrete recommendations out and auto-saves them to a personal library — no hunting through chat history.

**Requirements:**

- **Strict extraction schema** (`has_exercise_advice` + recommendations with name, description, muscle groups, sets/reps/rest/duration, difficulty, plan_name) — guaranteed well-formed output.
- **Keyword-gated** so non-exercise chats don't spend an extra API call.
- **Deduped by name** (case-insensitive); duplicates are silently skipped.
- **Workouts screen:** each card supports **Copy** (clipboard), **Ask** (a follow-up coach turn about that exercise), **Log it** (re-runs the exercise through the parsing pipeline and saves it as today's exercise entry), and remove.
- **Routines:** a named plan ("Leg Day A") groups its exercises via `plan_name`.

### Feature 9: Daily Log Reminders

**Status:** Built.

**Description:** A user-settable daily local notification that only nudges when the day still has gaps.

**Requirements:**

- Settings → Daily reminder: on/off switch + time picker.
- `flutter_local_notifications` with `timezone` (device-local IANA zone via `flutter_timezone`).
- **Inexact daily scheduling** (`AndroidScheduleMode.inexactAllowWhileIdle`) — no exact-alarm permission needed on Android.
- **Gap-aware nudge:** at every re-arm point (app launch, foreground resume, after each log add/delete, settings change) the message is chosen from today's entries — nothing logged → "What did you eat today?"; breakfast/lunch/dinner missing (snacks never count) → "Anything else today? (…)"; meals complete but no workout → "Did you get your workout in?"; a complete day → silent today but the daily repeat is re-armed for tomorrow (never cancelled, or the reminder would die until the app is next opened); a switched-off reminder → cancelled.
- **Re-armed on every app launch**, plus a boot receiver (`ScheduledNotificationBootReceiver` + `RECEIVE_BOOT_COMPLETED`) so a reboot does not silently drop the schedule.
- **Android manifest:** `flutter_local_notifications` v16+ no longer declares its own receivers — the app must declare `ScheduledNotificationReceiver`, or scheduled alarms fire into nothing and no reminder is ever shown.
- Runtime permission flow for iOS and Android 13+.

### Feature 10: First-run profile & maintenance estimate

**Status:** Built.

**Description:** On a brand-new install the app asks a few quick questions
(height, weight, date of birth, sex, activity level) so the daily
maintenance-calorie target is *estimated* instead of guessed. Existing
installs (any logs, a weigh-in, or a stored maintenance target) skip the
questionnaire entirely.

**Requirements:**

- **Onboarding gate:** the shell shows the questionnaire until the profile is
  completed (`app_settings.profile_completed`) — there is no skip, so the
  target is personal from the first day; fresh installs only.
- **Flow, not a form:** a 4-step onboarding (height → weight → birthday & sex →
  activity) with a progress bar, Back/Continue buttons and per-step
  validation.
- **Questions:** height (cm or ft/in), current weight (kg/lb — saved as
  today's first weigh-in), **date of birth** (a calendar picker — age is
  derived from it on the fly, so it never goes stale), sex, activity level
  (5 options, 1.2–1.9 factors).
- **Mifflin-St Jeor estimate:** `BMR = 10·kg + 6.25·cm − 5·age + (5 | −161)`,
  maintenance = BMR × activity factor. Shown live on the final step and
  written to the existing `maintenance_kcal` target — the single line the
  calendar, budgets, streaks and coach all measure against.
- **The target IS the estimate (fool-proof editing):** Settings → Targets &
  profile shows the maintenance number as a **display-only readout** that
  re-calculates the instant any profile input (height, birthday, sex,
  activity) changes, using the latest weigh-in for current weight. There is
  no hidden "apply" step — a regular user just sees the number react.
- **Manual override is opt-in:** a clearly-labelled "Set my own target"
  toggle reveals a number field (with a "your profile suggests X" comparison
  line and a one-tap "Back to automatic" reset), so a professional's
  recommendation is still possible without confusing everyone else. A
  hand-set target pauses the weight sync — a weigh-in never silently
  overrides an explicit number.
- **The target follows your weight (always on):** logging a weigh-in that
  moves the weight by ≥ 0.5 kg (daily water-weight wobble is ignored)
  recomputes the target. Once there are ≥ 14 days between weigh-ins and ≥ 10
  days of food logs, it uses the observed estimate
  (`avg daily intake + Δkg × 7,700 / days`) from the "From your logging" card,
  clamped to ±15% of the formula estimate so a skipped week can never halve or
  double the target; with too little logging it falls back to the formula from
  the new weight, so even a brand-new user's target reacts to their first
  weigh-in. Logged workouts already live inside the weight trend, so they are
  never double-counted. The weigh-in sheet reports the new number ("target
  updated to X kcal").

## 5. The Backend (Go Service)

**Status:** Built.

### 5.1 Purpose

The backend exists to keep the AI provider key off the device and to meter AI
spend. It is also the account and subscription authority, and it serves the
public website. It never stores the user's log content.

### 5.2 Stack

- Go, standard `net/http` + `chi` router.
- Postgres via `pgx` (no ORM); migrations with `goose`, embedded in the binary.
- JWT (HS256) for app sessions.
- Configuration from environment variables only, validated at startup.
- Structured logging with `log/slog`.
- One static binary; migrations applied by a separate command.

### 5.3 Layout

    cmd/api          the HTTP service
    cmd/migrate      applies the embedded SQL migrations
    internal/auth    JWT issue/verify; Google ID-token verification
    internal/ai      Provider interface, OpenAI implementation, prompts/schemas, fake provider
    internal/http    router, middleware, handlers
    internal/site    serves the embedded public site
    internal/store   pgx persistence
    internal/entitlements  RevenueCat webhook -> entitlement state
    internal/limits  daily quotas + global spend cap
    migrations       embedded goose SQL
    web              Vite + React + TypeScript public site (pre-rendered, embedded)
    webassets.go     embeds web/dist into the binary

### 5.4 HTTP API

| Method & path | Purpose |
|---|---|
| `POST /v1/auth/anonymous` | `{install_id}` -> `{token, user_id}`; creates/looks up the device account, counting the per-device free-account cap. |
| `POST /v1/auth/google` | `{id_token, install_id}` -> `{token, user_id, linked}`; verifies the Google token, stores only the subject, links an anonymous session when present. |
| `GET /v1/me` | User, entitlement, per-kind remaining limits for today, and remaining daily spend. |
| `DELETE /v1/me` | Deletes the account, its entitlement and usage, and its stored RevenueCat event copies. Idempotent (204). |
| `POST /v1/webhooks/revenuecat` | RevenueCat webhook; `Authorization` secret compared in constant time; idempotent on the event id. |
| `POST /v1/ai/transcribe` | multipart `file` (25 MiB cap), optional `prompt` -> `{text}`. |
| `POST /v1/ai/parse` | Auto-detect meal vs workout from a transcript. |
| `POST /v1/ai/parse-meal`, `POST /v1/ai/parse-exercise` | Biased parse variants. |
| `POST /v1/ai/chat` | Coach reply. |
| `POST /v1/ai/distill-memories`, `POST /v1/ai/extract-exercises` | Strict-schema helper calls. |
| `GET /healthz` | Liveness/readiness. |
| `GET /`, `/privacy`, `/terms`, `/delete-account` | Public website (see §5.11). |

Every authenticated AI route runs the same pipeline: authenticate → check
entitlement → check limits and the global spend cap → call the provider → record
usage → respond. Errors use a single JSON envelope
`{"error":{"code":"…","message":"…"}}`.

### 5.5 Authentication

- A session is a JWT signed with `JWT_SECRET` (default TTL 720h). The app sends it
  as `Authorization: Bearer <token>`.
- Anonymous sign-in keys the account on a random `install_id`. A per-device daily
  cap (default 1) limits how many free accounts one device can create; the cap
  counts a salted, one-way hash of the client IP, never the raw address.
- Google sign-in verifies the ID token's signature, expiry and audience
  (`GOOGLE_WEB_CLIENT_ID`) and uses only the `sub` claim. No email, name or photo
  is stored.

### 5.6 Entitlements (RevenueCat)

- One entitlement row per user, mirrored from RevenueCat webhook events. The app
  user id RevenueCat uses is our own user id.
- Statuses: `active`, `grace` (billing issue, still in the grace period),
  `expired`, and `cancelled_active` (cancelled but still inside the paid period).
  An entitlement is "active" when its status grants it *and* it has not passed
  `expires_at`.
- The webhook is authenticated by a shared secret in the `Authorization` header
  (compared in constant time) and is idempotent on the RevenueCat event id —
  recording the event and applying the entitlement change happen in one
  transaction, so a retry re-applies rather than being dropped as a duplicate.
- Mapped event types: initial purchase, renewal, cancellation, uncancellation,
  non-renewing purchase, subscription paused, expiration, billing issue, product
  change, subscription extended, refund reversed, temporary entitlement grant,
  price-increase consent, invoice issuance, purchase redeemed. `TRANSFER` is
  recorded but **not applied** (see §10).

### 5.7 Metered AI proxy

- The vendor sits behind a small `Provider` interface (`Transcribe`, `Structured`,
  `Chat`) so it can be swapped; the OpenAI implementation is the default and a
  fake provider backs the tests.
- Default models: `gpt-transcribe` for transcription, `gpt-4o-mini` for parsing;
  both overridable by env. Prompts and strict JSON schemas live in `internal/ai`.
- Every call carries the request context, so a cancelled request or the request
  timeout aborts it; the provider response size is capped.

### 5.8 Limits & abuse protection

- **Per-kind daily limits,** free vs paid, live in code (`internal/limits`), not
  the database:

  | Kind | Free / day | Paid / day |
  |---|---|---|
  | transcription | 10 | 300 |
  | meal/workout parse (and auto) | 20 | 1000 |
  | coach chat | 20 | 1000 |
  | memory distill | 20 | 500 |
  | exercise extract | 20 | 500 |

- **Global daily spend cap** (default \$25) — once today's estimated spend reaches
  it, the AI routes return a friendly `503`.
- **Rate limits** per IP (default 60/min) and per authenticated user (default
  30/min).
- **Per-device free-account cap** (default 1/day) via the salted IP hash.

### 5.9 Server data model

- `users(id uuid pk, install_id text unique, google_sub text null, created_at)`
- `entitlements(user_id uuid pk -> users, entitlement text, status text, expires_at timestamptz null, updated_at)`
- `revenuecat_events(event_id text pk, received_at, payload jsonb)` — idempotency.
- `usage(id bigserial pk, user_id, kind text, units numeric, cost_estimate numeric, created_at)` with an index on `(user_id, created_at)`.
- `daily_spend(day date pk, cost_estimate numeric)` — global, not per user.
- `device_signups(ip_hash text, day date, count int)` — the per-device signup cap.

No meal, workout, weigh-in or chat content is stored server-side.

### 5.10 Configuration

Config is environment-only and validated at startup, so a bad deploy crash-loops
rather than serving with missing settings. Required: `DATABASE_URL`, `JWT_SECRET`,
`GOOGLE_WEB_CLIENT_ID`. Everything else has a default: HTTP address, log level,
request/shutdown timeouts, JWT TTL, the abuse limits above, the AI provider base
URL/models/timeout, the RevenueCat webhook secret and entitlement id, and the
trusted-proxy networks (Caddy on loopback by default). See `backend/.env.example`.

### 5.11 Public website

- The same binary serves the marketing and legal pages: home, privacy policy,
  terms of service, and the account-deletion page Play requires.
- It is a Vite + React + TypeScript project under `backend/web`, **pre-rendered to
  static HTML** at build time (readable with JavaScript disabled) and embedded in
  the binary. It is served as the router's fallback, so API routes always win and
  an unknown path returns a real 404 rather than an index fallback.
- All app-specific text (name, developer, support email, Play URL, site URL, the
  legal copy) lives in one file, `backend/web/src/config.ts`, so the template can
  be reused for another app by editing that file.
- All `{{PLACEHOLDER}}` markers are filled (app name, developer, support email,
  Play URL, site URL, deletion turnaround, governing law — the Federal Republic
  of Nigeria). The site build fails on any marker left when run with
  `SITE_STRICT_PLACEHOLDERS=1`. The legal text is still a **draft that needs a
  qualified review** before publishing (see §10).

### 5.12 Ops & deployment

- `GET /healthz`; graceful shutdown that drains in-flight requests.
- Request-ID logging; access logs record routing metadata only — never headers,
  bodies, tokens, audio or user text.
- Deployed as a systemd service behind Caddy on a Contabo VPS, with Postgres on
  the same host. Migrations run via `ExecStartPre` before the API starts. `make
  web` builds the embedded site; `make build`/`test`/`vet`/`run` depend on it.
- A container path exists too: `backend/Dockerfile` (multi-stage, distroless
  runtime holding only the two static binaries) and `backend/docker-compose.yml`
  (Postgres + one-shot migrate + API), wrapped by `make docker`/`docker-up`/
  `docker-down`/`docker-reset`. systemd behind Caddy remains the primary VPS path.

## 6. App Technical Specifications

### Implementation Stack (Built)

- **Framework:** Flutter — iOS and Android targets (web considered a future target)
- **State management:** flutter_riverpod (Riverpod 3)
- **Local persistence:** SQLite via `sqflite` (offline-first) — schema v4 with migration
- **Secure storage:** `flutter_secure_storage` — iOS Keychain / Android EncryptedSharedPreferences (session token + vocabulary)
- **Audio capture:** `record` (.m4a, live amplitude stream for the waveform)
- **Notifications:** `flutter_local_notifications` + `timezone` (+ `flutter_timezone` for the local IANA zone)
- **Networking:** `http` — outbound AI calls go to the Weight Buddy backend, which calls the AI provider; Google sign-in uses `google_sign_in`; external legal pages open via `url_launcher`
- **Typography:** `google_fonts` — IBM Plex Mono for data, Karla for text
- **App id:** `com.tedif.weight_buddy` (Android `applicationId`/namespace + iOS bundle identifier)
- **Settings organization:** a hub menu fans out to focused pages — **Account & voice** (session, today's allowance, vocabulary), **Targets & profile** (maintenance, profile), **Daily reminder**, **Data** (demo + delete-all), and **Legal & privacy** (privacy policy, terms, account deletion).

### AI Integration (through the backend)

- **Transcription:** the app uploads the recording to `POST /v1/ai/transcribe`
  (`file`, optional `prompt`). The backend calls the provider's transcription
  endpoint (`/audio/transcriptions`); model default `gpt-transcribe`.
- **Parsing:** the transcript (or typed text) is sent to `/v1/ai/parse-meal`,
  `/v1/ai/parse-exercise` or the auto `/v1/ai/parse`, returned as strict JSON.
- **Prompt model:** `gpt-4o-mini` with strict JSON Schema (overridable).

### Structured Output Schemas

All schemas are **fully strict-mode compliant** — every property is in `required`, optional fields use nullable unions (`["number", "null"]`, `["string", "null"]`) — so responses are guaranteed well-formed.

> **Division of labour:** the model only ever *parses* (structure, portions, names). Calories for meals are estimated by the model from portion sizes; calories for **exercises are never estimated by the model** — `estimated_calories_burned` is always `null` in its reply and the app prices the burn locally with the deterministic engine below, using the user's latest weigh-in.

#### Meal & Macro Schema Example

**Transcript Example:** "I had two plates of jollof rice with two pieces of fried chicken and fried plantain"

**JSON Output Structure:**

```json
{
  "entry_type": "meal",
  "summary": "Jollof rice with 2 pieces fried chicken and fried plantain",
  "meal_type": "lunch",
  "items": [
    {
      "name": "Jollof Rice",
      "quantity": "2 plates",
      "calories": 700,
      "protein_g": 14,
      "carbs_g": 110,
      "fat_g": 20
    },
    {
      "name": "Fried Chicken",
      "quantity": "2 pieces",
      "calories": 400,
      "protein_g": 38,
      "carbs_g": 0,
      "fat_g": 22
    },
    {
      "name": "Fried Plantain",
      "quantity": "1 serving",
      "calories": 250,
      "protein_g": 1.5,
      "carbs_g": 48,
      "fat_g": 8
    }
  ],
  "total_calories": 1350,
  "total_protein_g": 53.5,
  "total_carbs_g": 158,
  "total_fat_g": 50
}
```

#### Exercise Schema Example

**Transcript Example:** "I ran on the treadmill for 30 minutes at a moderate pace" — or "I did 5 knee press-ups and 5 dips" (every exercise becomes its own entry in `exercises`).

**JSON Output Structure:**

```json
{
  "entry_type": "exercise",
  "summary": "5 knee press-ups and 5 dips",
  "meal_type": null,
  "activity": "Knee Press-ups",
  "duration_minutes": null,
  "estimated_calories_burned": null,
  "exercises": [
    {
      "name": "Knee Press-ups",
      "sets": 1,
      "reps": 5,
      "duration_minutes": null,
      "estimated_calories_burned": null
    },
    {
      "name": "Dips",
      "sets": 1,
      "reps": 5,
      "duration_minutes": null,
      "estimated_calories_burned": null
    }
  ]
}
```

A workout is saved as a **single daily-log entry** — one timeline row with the
spoken session's exercises nested underneath as items, the mirror image of a
meal's food items ("5 knee press-ups and 5 dips" lands as one entry titled
"Knee Press-ups + 1 more"). The single
`activity`/`duration_minutes`/`estimated_calories_burned` fields are a legacy
shape and mirror the first array entry; the `exercises` array is the source
of truth for what gets logged. The `sets`/`reps`/`duration_minutes` fields
are the burn engine's inputs and are persisted on the log row for a
single-exercise workout, and inside each nested exercise item otherwise.

### Exercise Burn Engine (deterministic, non-inflated)

The burn is computed in `lib/utils/exercise_math.dart` — pure math, no LLM,
no I/O — the same way `CalorieMath` prices the maintenance target.

**Method 1 — mechanical work (reps win).** Bodyweight strength is priced by
the work actually performed against gravity, divided by ~22% muscular
efficiency:

```text
work (J) = mass(kg) × 9.81 × vertical displacement(m) × reps
kcal     = work (J) ÷ (4,184 × 0.22)          ← 4,184 J per dietary kcal
```

Vertical displacement constants:
- Dips: **0.40 m** × full bodyweight
- Pull-ups: **0.50 m** × full bodyweight
- Push-ups: **0.25 m** × ~65% bodyweight (hands carry the rest)
- Squats / lunges: **0.45 m** × full bodyweight
- Unknown movements: conservative **0.40 m** × full bodyweight

**Method 2 — MET on precise seconds (duration only).** When no reps were
said, the burn is priced on the exact minutes active — never rounded up to a
minimum session block:

```text
kcal = MET × 3.5 × weight(kg) ÷ 200 × duration(minutes)
```

MET defaults to **8.0** (vigorous calisthenics, Compendium of Physical
Activities) with per-activity values for common cardio (running ≈ 9.8, brisk
walk ≈ 4.3, cycling ≈ 7.5, …).

**Verification (mirrors the unit tests in `test/exercise_math_test.dart`):**
20 bodyweight dips @ 87 kg → `87 × 9.81 × 0.4 × 20 = 6,828 J` → **≈ 7.4 kcal**
(inside the 6–10 kcal band; MET for a 45 s set ≈ 9.1 kcal). A single
20-rep set must never reach 20 kcal — the engine caps every set at
`maxKcalPerSet` as a guard against mis-parsed reps. The engine prices burns
only off the user's latest weigh-in; when the weight is unknown the burn is
zero rather than an invented number — the model is told to send
`estimated_calories_burned: null`, and the app never fabricates a figure.

## 7. Data Storage

### On the device (source of truth for the log)

- **Local persistence only:** SQLite via `sqflite`.
- **Schema v1:** `logs`: id, timestamp, type (meal/exercise), summary, calories, protein_g, carbs_g, fat_g, raw_transcript, items (JSON array of the entry's parsed items — food items for meals, exercise items for workouts).
- **Schema v2 (migrated via `onUpgrade`):**
  - `weigh_ins`: id, date, weight_kg, note.
  - `app_settings`: key/value KV for non-secret config (maintenance_kcal, reminder_enabled, reminder_time, memory_enabled, target_custom (hand-set target pause for weight sync; legacy installs omit it and the mode is inferred), plus the first-run profile: height_cm, birthday (ISO date; legacy `age` values are synthesised into a birthday on load), sex, activity_level, profile_completed).
  - `chat_messages`: id, role, content, created_at (persisted coach thread).
  - `memories`: id, topic, content, category, source, created_at, updated_at, active — unique active index on topic for latest-wins upsert.
  - `exercise_recommendations`: id, name, description, muscle_groups (JSON), sets, reps, rest_seconds, duration_minutes, difficulty, plan_name, source_chat_id, created_at, archived.
- **Schema v3 (migrated via `onUpgrade`):**
  - `logs` gains `meal_type` (breakfast/lunch/dinner/snack; legacy rows default to `meal`).
  - `day_maintenance`: day (local-midnight millis, PK) → maintenance_kcal — a per-day snapshot written whenever a log is added, so past days are judged by the target in effect that day.
- **Schema v4 (migrated via `onUpgrade`):** `logs` gains `sets`, `reps` and `duration_minutes` (nullable) — the structured exercise context the burn was computed from, so logged workouts keep their sets × reps and duration.
- **Demo data (debug builds):** Settings → Data → "Load demo data" (hidden in release builds) replaces the records with a realistic busy dataset — ~14 days of tagged meals and workouts, a weigh-in trend, a coach conversation, memories and a saved exercise library. Idempotent via a `demo_seeded` marker; sign-in and targets are preserved.
- **Delete all (full reset):** Settings → Data → "Delete all entries" wipes every record, clears `app_settings` (profile, maintenance target, reminder, memory switch, demo marker) and clears the stored session from the secure store, then pops back to the shell where the first-run onboarding questionnaire appears again — the app returns to a state indistinguishable from a brand-new install.
- **Secrets** (session token, vocabulary) stay in the platform secure store, never in SQLite.

### On the server (metadata only)

See §5.9. The server stores an account identifier, entitlement state, usage
counts/costs, the abuse hash and stored webhook copies — never meal, workout,
weigh-in or chat content. Account deletion removes all of it.

## 8. Non-Functional Requirements

- **Transcription precision:** high handling of non-Western, regional or local culinary names, via AI-provider transcription (with a custom vocabulary) rather than native device speech recognisers.
- **Latency:** the two-stage pipeline (transcription → structured parse) completes in a few seconds on a normal mobile connection.
- **Privacy & data ownership:** the log is offline-first and lives on the device; AI content is sent to the AI provider through our server and is not stored or logged by us; the server keeps only account/entitlement/usage metadata.
- **Resilience:** the AI routes answer a friendly `503` when the provider key is unset or the global spend cap is reached, rather than failing hard.
- **Accessibility:** visible keyboard focus, ≥44dp touch targets, screen-reader summaries on the Day's Wave, and `prefers-reduced-motion` respected (the peak draw-in animation is skipped).

## 9. Design & Identity

- **Direction:** "the pot and the plate" — a deep roasted-cocoa night kitchen, lit by the food itself. Warm brown-black ground, raised bark surfaces, hairline ember separators.
- **Palette:** `pot #221A17` (background) · `bone #F4EAD9` (text) · `jollof #E85D2F` (primary / meals) · `plantain #F2B53C` (accent / protein) · `ugu #5CA96C` (exercise) · `suya #C08A5A` (fat macro).
- **Typography:** IBM Plex Mono for every number (kitchen-scale readouts); Karla for reading text; small-caps mono labels.
- **Signature:** the Day's Wave — the day's logs drawn as a waveform on the dashboard, echoed live on the record sheet while speaking.
- **Launcher identity:** app id `com.tedif.weight_buddy`; launcher icon is the Day's Wave (jollof bars with a plantain centre peak) on the pot background, generated with `flutter_launcher_icons`.

## 10. Status & Open Items

Known gaps between what is built and what the product intends. The first four are
the ones that matter before shipping.

1. **Subscription is modelled but not purchasable.** The backend handles the paid
   entitlement (RevenueCat webhook + paid-tier limits), but the app ships no
   purchase SDK — `mobile/lib/data/revenuecat_identity.dart` is a no-op seam — so
   no subscription can be bought today. Wire RevenueCat in the app to ship it.
2. **Legal/branding text is a draft.** `backend/web/src/config.ts` still contains
   `{{DEVELOPER_NAME}}`, `{{SUPPORT_EMAIL}}`, `{{PLAY_STORE_URL}}`, `{{SITE_URL}}`,
   `{{GOVERNING_LAW}}` and `{{DELETION_DAYS}}`; the site build warns on these and
   can fail with `SITE_STRICT_PLACEHOLDERS=1`. Have the legal copy reviewed by a
   qualified person before publishing.
3. **RevenueCat REST fallback is not implemented** (the backend template's task 5):
   entitlement is read from the DB only, so a lost webhook leaves a paying user on
   free limits until the next event arrives. `/v1/me` reads the row directly.
4. **`TRANSFER` events are recorded but not applied.** A subscription transferred
   between app user ids does not move to the new account.
5. **Store SQL tests skip without `TEST_DATABASE_URL`**, and there is no CI
   configuration, so migrations and the hand-written queries run only when a
   developer points at a scratch database.
6. **The real Google token-verifier path is untested** (tests inject a fake
   verifier).
7. **Rate limiting and the spend cap are process-local** (single instance).
8. **Dead code:** `Store.Pool()` has no callers; `CreateOrGetUser` and
   `UpsertEntitlement` are used only by tests.
9. **Site screenshots** on the home page are placeholders.
