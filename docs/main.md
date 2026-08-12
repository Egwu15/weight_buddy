# Lean PRD: Lightweight Voice Calorie, Macro & Exercise Tracker

> **Status:** Implemented as a Flutter app (v3.0). This document is the source of truth for what was built; features marked **Built** are implemented and tested.

## 1. Product Overview

A personal, lightweight mobile/web application that allows a single user to log meals and workouts by voice — with typed input as a fallback for noisy rooms, mic failures or tired voices. To reliably capture localized or regional dish names that standard native phone speech recognizers misinterpret, the application routes recorded audio through OpenAI's Audio API (whisper-1 or gpt-transcribe). Transcripts are then processed via GPT API to extract food items, calculate estimated calories, and calculate macronutrients (Protein, Carbs, Fat) or exercise calorie burn.

### Goals

- **Frictionless Voice Logging:** Eliminate manual database searching through natural spoken input.
- **High Transcription Accuracy for Local Foods:** Use OpenAI's Speech-to-Text API instead of local device engines to correctly parse unique or regional culinary names.
- **Macronutrient Tracking:** Automatically estimate daily Protein, Carbohydrate, and Fat totals alongside caloric intake.
- **Minimalist BYOK Architecture:** Run locally using the user's own OpenAI API key with zero cloud backend or subscription requirements.

## 2. Target User & Use Case

- **Primary User:** Single personal owner tracking daily nutrition and exercise.
- **Core Scenario:** User taps record and speaks what they ate (including regional/local dishes) or what exercise they performed — or types it instead when the room is noisy — and receives an instant breakdown of calories, macros, or calories burned.

## 3. Core Functional Requirements

### Feature 1: Bring-Your-Own-Key (BYOK) & Custom Vocabulary Settings

**Status:** Built.

**Description:** Settings view to store OpenAI API credentials and tune voice recognition vocabulary.

**Requirements:**

- Secure local storage for OpenAI API Key — iOS Keychain / Android EncryptedSharedPreferences via `flutter_secure_storage`. The full key never appears in the UI or the on-device database.
- Optional input field for Custom Vocabulary Hints (e.g., a comma separated list of local dish names like "Jollof, Egusi, Amala, Suya, Akara, Dodo") passed to the transcription API prompt parameter to boost recognition accuracy.
- Masked API key with basic validation before saving. After saving, the key is shown only as its last few characters (`sk-••••••••abcd`) with no reveal control; changing it uses a "Replace key" action.

### Feature 2: Voice Meal Logging & Macro Calculation

**Status:** Built.

**Description:** Convert recorded speech (or typed text) into structured food records including calories, macronutrients and a meal-type label.

**Requirements:**

- **Audio Capture & API Transcription:** Record raw audio on-device (e.g., .m4a or .wav) and post directly to OpenAI Audio API (/v1/audio/transcriptions).
- **Typing fallback:** the record sheet's idle view offers **"Type instead"** — a multiline field runs the same GPT parse pipeline as voice (skipping transcription), so logging still works in noisy places or when the mic is unavailable.
- **No-key onboarding:** with no saved OpenAI key, the sheet explains what's needed and offers **"Go to Settings"**, which closes the sheet and jumps straight to the Settings tab.
- **GPT Meal & Macro Analysis:** Send transcribed text to GPT API using Structured Outputs (JSON Schema).
- **Extracted Attributes:**
  - Food items with estimated portion sizes
  - Calories (kcal)
  - Protein (g)
  - Carbohydrates (g)
  - Fat (g)
  - Meal-type classification (breakfast / lunch / dinner / snack), inferred from the food + current local time and user-adjustable on the confirm card
- Display a confirmation card showing the parsed items, macro breakdown and a meal-type picker before persisting to local logs.

### Feature 3: Voice Exercise Logging & Burn Calculation

**Status:** Built.

**Description:** Convert recorded speech (or typed text) describing physical activity into calorie burn estimates.

**Requirements:**

- Transcribe recorded audio via OpenAI Audio API.
- Send transcript to GPT API to evaluate workout type, duration, intensity, and estimated calories burned.
- Append confirmed activity to the daily workout log.

### Feature 4: Daily Dashboard (Calories & Macros)

**Status:** Built.

**Description:** Single-screen view displaying daily progress and raw activity logs.

**Requirements:**

- **Calorie Summary Card:** Total Calories Consumed, Total Calories Burned, Net Calories, and **Left** — maintenance minus net (green when the day is still under budget, jollof when over).
- **Period glance:** under the daily ledger, a compact readout of what's left for the current **week** and **month** (budget − net), tappable through to the Month tab for the full period view.
- **Macro Summary Card:** Daily totals for Protein (g), Carbohydrates (g), and Fat (g).
- **Day's Wave (signature):** Today's entries are drawn as a waveform — each peak is one entry, height follows calories, colour follows type (meal / exercise), position follows time of day. Tapping a peak reveals its summary; an empty day is a flatline invitation to log.
- **Log Timeline:** Chronological feed of meals (with macro details) and workouts logged for the active date.
- Delete/remove capability for individual log entries.

### Feature 5: Month Calendar, Maintenance Colors & Streaks

**Status:** Built.

**Description:** A month-at-a-glance calendar that tints every day by its balance against the maintenance-calorie target, with consecutive-day streaks up top.

**Requirements:**

- **Maintenance target setting:** user-configurable daily maintenance calories (Settings → Targets), the line everything measures against.
- **Color coding:** a day with logs is tinted **ugu (green)** when net kcal ≤ maintenance, **jollof (red-orange)** when above, and stays neutral when nothing was logged.
- **Per-day maintenance snapshots:** every log records the maintenance target in effect that day (`day_maintenance`); the calendar and the ON-PLAN streak judge each day by its own snapshot (falling back to the current target for legacy days).
- **Streaks:** LOG STREAK (consecutive days with ≥1 entry) and ON-PLAN (consecutive days logged *and* at/below maintenance), computed from the last 90 days.
- **Week & month budget summaries:** two ledger cards above the calendar. The month card follows the existing month navigation; the week card (Monday–Sunday) has its own prev/next arrows. **LEFT** = period budget − net, where the budget is every day in the period at its maintenance target (per-day snapshot, falling back to the current target for days never logged).
- **Navigation:** tapping a calendar day jumps the Today dashboard to that day.
- Weight unit setting (kg/lb) lives in the same Targets section.

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

**Description:** A persistent chat with the user's own OpenAI key (BYOK) that is fed a digest of their live data plus a distilled, editable memory layer.

**Requirements:**

- **Context digest** assembled per message: maintenance target, today's totals, last 7 days, weight trend, streaks, active memories, saved exercises.
- **Chat thread persisted locally** (`chat_messages`); one conversation with a "new conversation" reset (memories/exercises survive resets).
- **Memory layer:** every ~4 exchanges a strict-schema GPT call distils `{topic, content, category, action: create|update|remove}` facts; upsert is latest-wins per topic; stale facts can be retired by the model.
- **Memory manager screen:** view/edit/add/delete memories, source label (you said / coach learned), and a master **"Let the coach remember"** switch that stops both writes and injection.
- **Privacy:** memories live only on-device and travel to OpenAI solely as chat context, matching the rest of the coach.

### Feature 8: Auto-Saved Exercise Recommendations

**Status:** Built.

**Description:** When the coach gives exercise advice, a strict-schema extraction call pulls the concrete recommendations out and auto-saves them to a personal library — no hunting through chat history.

**Requirements:**

- **Strict extraction schema** (`has_exercise_advice` + recommendations with name, description, muscle groups, sets/reps/rest/duration, difficulty, plan_name) — guaranteed well-formed output.
- **Keyword-gated** so non-exercise chats don't spend an extra API call.
- **Deduped by name** (case-insensitive); duplicates are silently skipped.
- **Workouts screen:** each card supports **Copy** (clipboard), **Ask** (a follow-up coach turn about that exercise), **Log it** (re-runs the exercise through the GPT parsing pipeline and saves it as today's exercise entry), and remove.
- **Routines:** a named plan ("Leg Day A") groups its exercises via `plan_name`.

### Feature 9: Daily Log Reminders

**Status:** Built.

**Description:** A user-settable daily local notification that only nudges when the day still has gaps.

**Requirements:**

- Settings → Reminder: on/off switch + time picker.
- `flutter_local_notifications` with `timezone` (device-local IANA zone via `flutter_timezone`).
- **Inexact daily scheduling** (`AndroidScheduleMode.inexactAllowWhileIdle`) — no exact-alarm permission needed on Android.
- **Gap-aware nudge:** at every re-arm point (app launch, foreground resume, after each log add/delete, settings change) the message is chosen from today's entries — nothing logged → "What did you eat today?"; breakfast/lunch/dinner missing (snacks never count) → "Anything else today? (…)"; meals complete but no workout → "Did you get your workout in?"; a complete day or a switched-off reminder → cancelled, silent.
- **Re-armed on every app launch** (Android does not persist schedules across reboots).
- Runtime permission flow for iOS and Android 13+.

### Feature 10: First-run profile & maintenance estimate

**Status:** Built.

**Description:** On a brand-new install the app asks a few quick questions
(height, weight, age, sex, activity level) so the daily maintenance-calorie
target is *estimated* instead of guessed. Existing installs (any logs, a
weigh-in, or a stored maintenance target) skip the questionnaire entirely.

**Requirements:**

- **Onboarding gate:** the shell shows the questionnaire until the profile is
  completed or skipped (`app_settings.profile_completed`); fresh installs only.
- **Questions:** height (cm), current weight (kg/lb — saved as today's first
  weigh-in), age, sex, activity level (5 options, 1.2–1.9 factors).
- **Mifflin-St Jeor estimate:** `BMR = 10·kg + 6.25·cm − 5·age + (5 | −161)`,
  maintenance = BMR × activity factor. Shown live on the questionnaire and
  written to the existing `maintenance_kcal` target — the single line the
  calendar, budgets, streaks and coach all measure against.
- **Editable later:** Settings → Targets gains a Profile section (height, age,
  sex, activity) plus a "Use profile to estimate maintenance" action that
  pre-fills the manual field from the profile + latest weigh-in. A manual
  value is never overwritten without pressing that button.

## 4. Technical Specifications & API Integration

### Implementation Stack (Built)

- **Framework:** Flutter — iOS and Android targets (web considered a future target)
- **State management:** flutter_riverpod (Riverpod 3)
- **Local persistence:** SQLite via `sqflite` (offline-first) — schema v3 with migration
- **Secure storage:** `flutter_secure_storage` — iOS Keychain / Android EncryptedSharedPreferences (BYOK key + vocabulary)
- **Audio capture:** `record` (.m4a, live amplitude stream for the waveform)
- **Notifications:** `flutter_local_notifications` + `timezone` (+ `flutter_timezone` for the local IANA zone)
- **Networking:** `http` — outbound calls go only to OpenAI
- **Typography:** `google_fonts` — IBM Plex Mono for data, Karla for text
- **App id:** `com.tedif.weight_buddy` (Android `applicationId`/namespace + iOS bundle identifier)

### OpenAI Audio API Integration (Speech-to-Text)

- **Endpoint:** POST [https://api.openai.com/v1/audio/transcriptions](https://api.openai.com/v1/audio/transcriptions)
- **Model:** gpt-transcribe (whisper-1 also supported)
- **Parameters:**
  - `file`: Recorded audio binary
  - `prompt`: Optional custom phrase list containing local dish names to guide phonetic accuracy

### GPT Analysis Schemas (Structured Outputs)

Parsing model: `gpt-4o-mini` with OpenAI Structured Outputs (strict JSON Schema).

All schemas are **fully strict-mode compliant** — every property is in `required`, optional fields use nullable unions (`["number", "null"]`, `["string", "null"]`) — so responses are guaranteed well-formed.

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

**Transcript Example:** "I ran on the treadmill for 30 minutes at a moderate pace"

**JSON Output Structure:**

```json
{
  "entry_type": "exercise",
  "summary": "30 min moderate treadmill run",
  "meal_type": null,
  "activity": "Treadmill Running",
  "duration_minutes": 30,
  "estimated_calories_burned": 300
}
```

### Data Storage Architecture

- **Local Persistence Only:** SQLite via `sqflite` (Hive/IndexedDB were considered and not chosen).
- **Schema v1:** `logs`: id, timestamp, type (meal/exercise), summary, calories, protein_g, carbs_g, fat_g, raw_transcript, items (JSON array of parsed food items for meals).
- **Schema v2 (migrated via `onUpgrade`):**
  - `weigh_ins`: id, date, weight_kg, note.
  - `app_settings`: key/value KV for non-secret config (maintenance_kcal, weight_unit, reminder_enabled, reminder_time, memory_enabled, plus the first-run profile: height_cm, age, sex, activity_level, profile_completed).
  - `chat_messages`: id, role, content, created_at (persisted coach thread).
  - `memories`: id, topic, content, category, source, created_at, updated_at, active — unique active index on topic for latest-wins upsert.
  - `exercise_recommendations`: id, name, description, muscle_groups (JSON), sets, reps, rest_seconds, duration_minutes, difficulty, plan_name, source_chat_id, created_at, archived.
- **Schema v3 (migrated via `onUpgrade`):**
  - `logs` gains `meal_type` (breakfast/lunch/dinner/snack; legacy rows default to `meal`).
  - `day_maintenance`: day (local-midnight millis, PK) → maintenance_kcal — a per-day snapshot written whenever a log is added, so past days are judged by the target in effect that day.
- **Demo data (debug builds):** Settings → Your data → "Load demo data" (hidden in release builds) replaces the records with a realistic busy dataset — ~14 days of tagged meals and workouts, a weigh-in trend, a coach conversation, memories and a saved exercise library. Idempotent via a `demo_seeded` marker; OpenAI key and targets are preserved.
- **Secrets** (OpenAI key, vocabulary) stay in the platform secure store, never in SQLite.
- **Coach context** (digest + memories + saved exercises) travels to OpenAI only while chatting; everything else is offline-first.

## 5. Non-Functional Requirements

- **Transcription Precision:** High handling of non-Western, regional, or local culinary names via direct OpenAI API transcription instead of native device speech recognizers.
- **Latency:** Two-stage API pipeline (Audio Transcription -> GPT Structured Parsing) completing in under 4 seconds on normal mobile connection.
- **Privacy & Local Ownership:** Completely offline-first database; outbound API traffic goes exclusively to official OpenAI endpoints.
- **Accessibility:** Visible keyboard focus, ≥44dp touch targets, screen-reader summaries on the Day's Wave, and `prefers-reduced-motion` respected (the peak draw-in animation is skipped).

## 6. Design & Identity

- **Direction:** "the pot and the plate" — a deep roasted-cocoa night kitchen, lit by the food itself. Warm brown-black ground, raised bark surfaces, hairline ember separators.
- **Palette:** `pot #221A17` (background) · `bone #F4EAD9` (text) · `jollof #E85D2F` (primary / meals) · `plantain #F2B53C` (accent / protein) · `ugu #5CA96C` (exercise) · `suya #C08A5A` (fat macro).
- **Typography:** IBM Plex Mono for every number (kitchen-scale readouts); Karla for reading text; small-caps mono labels.
- **Signature:** the Day's Wave — the day's logs drawn as a waveform on the dashboard, echoed live on the record sheet while speaking.
- **Launcher identity:** app id `com.tedif.weight_buddy`; launcher icon is the Day's Wave (jollof bars with a plantain centre peak) on the pot background, generated with `flutter_launcher_icons`.
