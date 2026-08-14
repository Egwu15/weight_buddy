# Weight Buddy

A personal voice calorie, macro & exercise tracker. Log meals and workouts by
speaking — powered by your own OpenAI API key, with everything stored on-device.

## What it does

- **Hold to speak** — say what you ate ("two plates of jollof rice with two
  pieces of fried chicken") or how you moved ("ran on the treadmill for
  30 minutes").
- **OpenAI audio transcription** (`gpt-transcribe`) with a custom vocabulary of
  local dish names passed as the prompt, so regional foods are heard right.
- **Structured parsing** — the transcript is turned into a meal (items, calories,
  protein/carbs/fat) or an exercise (activity, sets, reps, duration) using
  OpenAI Structured Outputs with the JSON schemas from `docs/main.md`. Exercise
  burns are never guessed by the model — the app prices them with a
  deterministic engine (mechanical work for reps, MET for duration), so a
  20-rep set logs a few kcal, not a fake workout number.
- **Confirm before saving** — review the parsed items, tweak portion sizes, then
  save to the local log.
- **The day as a sound wave** — each entry is a peak on the dashboard (height ∝
  calories, colour = meal or exercise), so a day reads like a voice memo.
- **Month calendar & streaks** — every day is tinted against your maintenance
  target (green at/below, jollof above), with logging and on-plan streaks.
- **Weight tracking** — log weigh-ins (monthly is fine); the dashboard shows the
  latest reading, the 30-day delta, and a hairline trend line.
- **Coach chat** — a persistent conversation with the same BYOK key, fed your
  live numbers (today, last 7 days, weight, streaks) plus a memory layer it
  distils and you can edit, disable, or delete.
- **Auto-saved exercise plans** — ask the coach for a workout and every concrete
  exercise lands in a library you can copy, log to today, or ask follow-ups about.
- **Daily reminders** — a notification at a time you choose nudges you to log.
- **BYOK** — bring your own OpenAI API key; it lives in the platform secure
  vault and goes nowhere but OpenAI.

## Design

Dark "night kitchen" theme: roasted-cocoa ground (`#221A17`), jollof
(`#E85D2F`), plantain (`#F2B53C`), leaf-green `ugu` (`#5CA96C`). Numbers are set
in IBM Plex Mono (kitchen-scale readouts); reading text in Karla.

## Tech

- Flutter (mobile-first; iOS, Android)
- `flutter_riverpod` state, `sqflite` local database (schema v4 with migration),
  `flutter_secure_storage` for the API key, `record` for capture, `http` for the
  OpenAI API, `flutter_local_notifications` + `timezone` for reminders
- Fonts via `google_fonts` (cached locally after first load)

## Getting started

```sh
flutter pub get
flutter run
```

Open **Settings**, paste your OpenAI key (and optionally the dish names you say
most, comma-separated), save, and start logging by voice.

## Tests

```sh
flutter test
```

Covers the dashboard empty state, the record sheet's settings-gate, the BYOK
form, macro aggregation, local add/delete persistence, the v2 schema
(settings, weigh-ins, memories, exercises), streaks, the coach context digest,
the strict-schema OpenAI parsing/extraction methods, and the Month/Coach tabs.
