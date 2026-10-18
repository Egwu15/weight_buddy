# Weight Buddy: Google Play submission sheet

Everything needed for the Play Console, in the order the screens appear. Copy
blocks are ready to paste; notes in _italics_ are for us, not for Play.

## App identity

| Field | Value |
|---|---|
| Package name | `com.tedif.weight_buddy` |
| App name (Play Console) | Weight Buddy |
| App or game | App |
| Free or paid | Free |
| Default language | English (United Kingdom) |
| Version | `1.0.5` (versionCode `5`) |
| Category | Health & Fitness |

_At app creation Play fixes the package name. It cannot be changed later._

## 1. Main store listing

Play Console: **Grow users > Store presence > Main store listing**.

### App name (29 / 30)

```text
Weight Buddy: Calorie Tracker
```

### Short description (76 / 80)

```text
Log meals and workouts by voice. See calories, macros and your weight trend.
```

### Full description (1845 / 4000)

```text
Log what you eat and how you move, just by talking.

Weight Buddy turns a short voice note into a meal or workout entry with calories, protein, carbs and fat. There is no food database to search and no form to fill in. Type instead whenever you would rather not speak.

HOW IT WORKS
1. Tap the mic and say what you ate or how you moved.
2. Check the entry Weight Buddy shows you and edit anything that came out wrong.
3. Save it. Today's calories, macros and burn update straight away.

WHAT YOU GET
- Voice meal logging with calories, protein, carbs and fat
- Voice workout logging with a measured burn, based on your latest weigh-in
- A daily dashboard with eaten, burned, net and left, plus week and month budgets
- A month calendar with streaks and a colour for every day
- Weight tracking with a 30-day trend
- A coach that uses the data you already log and remembers what matters to you
- Saved exercises and routines
- A daily reminder that only speaks up when the day still has gaps
- A dark, quiet design made for one-handed use

BUILT AROUND LOCAL FOOD
Add the dish names you actually use, such as jollof, egusi, amala or suya, so they are heard correctly the first time.

FREE DAILY ALLOWANCE
Voice logging and coach replies have a daily limit. The free allowance is 10 voice transcriptions and 20 coach replies a day, shown in Settings.

YOUR LOG STAYS ON YOUR PHONE
Meals, workouts, weigh-ins, memories and chat live on your device. The server keeps only what it needs to run your account: an account id, subscription status and usage counts. It does not keep the content of what you say or ask.

PRIVACY AND TERMS
Read both at https://weightbuddy.com

Weight Buddy is a tracking tool, not medical advice. Talk to a qualified professional before you change your diet, exercise or treatment.

Questions or problems: contact@tedif.com
```

### Graphics

Play Console: same page, **Graphics** section.

| Field | File | Spec | Alt text |
|---|---|---|---|
| App icon | `icon-512.png` | 512 x 512, 32-bit RGBA PNG, 8.2 KB | Weight Buddy app icon: orange and gold waveform bars on a dark brown background. |
| Feature graphic | `feature-graphic-1024x500.png` | 1024 x 500, 24-bit RGB PNG, no alpha | Weight Buddy feature graphic: "Say it. It's logged." beside an example voice-logged meal with 612 kcal and macros. |
| Phone screenshot 1 | `screenshots/01-today.png` | 1080 x 1920, 24-bit RGB PNG | Today dashboard with the Day's Wave, calories eaten, burned, net and left, and the Log by voice button. |
| Phone screenshot 2 | `screenshots/02-month.png` | 1080 x 1920, 24-bit RGB PNG | Month calendar with logging streaks and days coloured against the maintenance target. |
| Phone screenshot 3 | `screenshots/03-coach.png` | 1080 x 1920, 24-bit RGB PNG | Coach chat with a saved exercise recommendation. |
| Phone screenshot 4 | `screenshots/04-weight-trend.png` | 1080 x 1920, 24-bit RGB PNG | Weight screen with a 30-day trend and weigh-in history. |

Upload the four phone screenshots in the order above.

| Field | Answer |
|---|---|
| 7-inch tablet screenshots | None. Play falls back to the phone screenshots. |
| 10-inch tablet screenshots | None. |
| Chromebook screenshots | None. |
| Preview video | None. Leave the YouTube field empty. |
| Play Shorts | None. |

_If tablet screenshots are added later, use 16:9 landscape or 9:16 portrait at_
_1080 px or larger and capture the app on a tablet-sized window._

## 2. Store settings

Play Console: **Grow users > Store presence > Store settings**.

| Field | Answer |
|---|---|
| App category | Health & Fitness |
| Tags | Add the closest available tags: Calorie tracker, Nutrition, Fitness. Maximum 5. |
| Contact email | contact@tedif.com |
| Contact phone | Leave empty. |
| Website | https://weightbuddy.com |
| External marketing | Leave checked so Google can promote the app. |

## 3. App content

Play Console: **Policy and programs > App content**.

### Privacy policy

```text
https://weightbuddy.com/privacy
```

### App access

Select **All functionality is available without special access**.

Notes for the reviewer, if a notes field is offered:

```text
No credentials are needed. On first launch the app creates an anonymous account automatically and opens onboarding. Google sign-in is optional and is not required to use any feature.
```

### Ads

```text
No
```

### Content rating

Start the questionnaire with the email `contact@tedif.com`. Choose the app
category **Utility, Productivity, Communication, or Other**, then answer:

| Question | Answer |
|---|---|
| Violence | No |
| Sexuality | No |
| Language | No |
| Controlled substances | No |
| Gambling | No |
| User interaction or content sharing | No. There is no user-to-user communication and no shared user content. |
| Shares current location | No |
| Digital purchases | No. The app has no purchase flow at launch. |
| Contains ads | No |
| Miscellaneous | No |

_Expected result: Everyone / PEGI 3 / rated 3+. The rating authorities make the_
_final decision._

### Target audience and content

| Field | Answer |
|---|---|
| Age groups | 13-15, 16-17, 18 and over |
| Is the app designed for children? | No |
| Could the app unintentionally appeal to children? | No |

_13+ matches the app, the site and the legal pages. Selecting 13-15 does not_
_trigger the Families policy because no group includes children under 13._

### Data safety

#### Data collection and security

| Question | Answer |
|---|---|
| Does your app collect or share any required user data types? | Yes |
| Is all user data encrypted in transit? | Yes |
| Do you provide a way for users to request that their data is deleted? | Yes, `https://weightbuddy.com/delete-account` |

#### Data types

| Category and type | Collected | Shared | Required or optional | Ephemeral | Purposes |
|---|---|---|---|---|---|
| Personal info > User IDs | Yes | No | Required | No | App functionality; Account management; Fraud prevention, security and compliance |
| Health and fitness > Fitness info | Yes | No | Required | No | App functionality |
| Messages > Other in-app messages | Yes | No | Optional | No | App functionality |
| Audio > Voice or sound recordings | Yes | No | Optional | No | App functionality |
| App activity > App interactions | Yes | No | Required | No | App functionality; Account management; Fraud prevention, security and compliance |
| Device or other IDs | Yes | No | Required | No | App functionality; Account management; Fraud prevention, security and compliance |

Data type notes:

- **User IDs:** a random install id becomes the account id. If the user signs in
  with Google, the stable Google subject id is stored. No email, name or photo.
- **Fitness info:** meals, macros, workouts, weigh-ins and the coach context are
  sent through the backend for processing. They are not stored as a log on the
  server.
- **Other in-app messages:** coach messages are sent for a reply. The server
  records only that the call happened.
- **Voice or sound recordings:** voice notes are sent for transcription only.
  Typing is available instead, so this is optional.
- **App interactions:** AI call counts and cost estimates, never content.
- **Device or other IDs:** install id plus a salted, one-way hash of the IP
  address used for the free-account cap. No advertising id.

Do not select: location, name, email, address, phone number, race, political or
religious beliefs, sexual orientation, financial info, purchase history,
health records, photos, videos, files, calendar, contacts, app search history,
installed apps, web browsing, crash logs or diagnostics. The app has no
analytics, crash-reporting or advertising SDK.

_No third-party sharing is declared: the AI provider and RevenueCat process data_
_on our behalf as service providers. The app does not store audio or text; the AI_
_provider handles it under its own terms, so it is declared as collected rather_
_than ephemeral._

### Account deletion

| Field | Answer |
|---|---|
| Does the app let users create an account? | Yes |
| In-app deletion path | Settings > Account & voice > Delete account |
| Web deletion URL | `https://weightbuddy.com/delete-account` |

_Deleting the account removes the server account, entitlement, usage history and_
_stored RevenueCat event copies. On-device meals, workouts and weigh-ins are_
_erased only when the user chooses that option or uninstalls the app._

### Health apps

Select both health features:

```text
Activity and Fitness
Nutrition and Weight Management
```

Additional information:

```text
Weight Buddy is a general wellness tracker for meals, exercise and weight. It is not a medical device, does not diagnose, treat or prevent any condition, and makes no medical claims. The app and listing tell users to speak to a qualified professional before changing their diet, exercise or treatment. It does not connect to Health Connect or any medical hardware.
```

### Other declarations

| Section | Answer |
|---|---|
| Financial features | No |
| Government apps | No |
| News and magazine apps | No |
| COVID-19 contact tracing and status | No |
| Advertising ID | No. The app does not use the advertising identifier. |
| Photo and video permissions | No. The backup flow uses the system file picker. |
| SMS and Call Log permissions | No. |

_Microphone: the app requests `RECORD_AUDIO` at runtime from the record sheet,_
_which explains that the recording is used to log a meal or workout. No_
_background audio access._

## 4. Pricing and distribution

Play Console: **Reach and devices > Pricing and distribution**.

| Field | Answer |
|---|---|
| App pricing | Free |
| Contains ads | No |
| In-app purchases | No at launch. The app ships no purchase SDK. |
| Countries and regions | All available countries and regions |
| Content guidelines | Yes, the app meets the guidelines |
| US export laws | Yes, the app complies |
| Device categories | Phones. Do not claim tablet, Chromebook, TV, Wear or Auto optimization. |

_If RevenueCat is wired into the app, change in-app purchases to Yes and add the_
_subscription products before shipping that build._

## 5. Release

Play Console: **Test and release > Production > Create new release**.

| Field | Answer |
|---|---|
| App bundle | `build/app/outputs/bundle/release/app-release.aab` |
| Version name | `1.0.5` |
| Version code | `5` |
| Signing | Play App Signing. The registered SHA-1 is already used by the review build. |
| Rollout | Start with internal testing, then closed testing, then production. |

### Release notes (first production release)

```text
First release. Log meals and workouts by voice, see today's calories and macros, follow your weight trend, and ask the coach for help.
```

_Only raise `MIN_APP_VERSION` after this version is at 100% rollout. A staged_
_rollout plus a raised minimum would lock out users who cannot yet download the_
_new build._

## 6. Force update

The app calls `GET /v1/app/version` at launch and on resume. An install older
than `minimum_version` sees a blocking update screen and cannot use the app.
This is the response once `1.0.5` becomes the minimum (the default `1.0.0`
forces nobody):

```json
{
  "minimum_version": "1.0.5",
  "store_url": "https://play.google.com/store/apps/details?id=com.tedif.weight_buddy",
  "message": "Update Weight Buddy to keep logging your meals and workouts."
}
```

Backend environment:

```sh
MIN_APP_VERSION=1.0.0
APP_STORE_URL=https://play.google.com/store/apps/details?id=com.tedif.weight_buddy
APP_UPDATE_MESSAGE=Update Weight Buddy to keep logging your meals and workouts.
```

To retire an old build, deploy the new build to 100% first, then set
`MIN_APP_VERSION` to that version and restart the API. The check fails open when
the endpoint is unreachable or the response is malformed, so an outage never
blocks offline logging. The endpoint is public and sends `Cache-Control:
no-store`.

## Notes

- User-visible copy uses no em dashes and does not name the AI provider.
- The free allowance line matches `backend/internal/limits/limits.go` (Free:
  10 transcribe, 20 parse/chat per day). Update the listing if those defaults
  change.
- The feature graphic reuses the app palette, wordmark and waveform mark, with an
  example voice entry card.
- The app has no purchase flow yet, so the listing does not mention a paid tier.
- Screenshots are captured at 1080 x 1920 and contain no service-provider names
  or notifications.
