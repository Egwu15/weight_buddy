# Roadmap

Planned and outstanding work, in rough order. This is where "what next" lives so `HANDOFF.md` can
stay short and disposable. Status details and rationale are in `main.md` (§10) and `journal.md`;
this file only sequences the work.

## Now — before shipping

- **Decide on subscriptions.** The backend already models a paid entitlement, but the app ships no
  purchase SDK (the RevenueCat seam is a no-op), so nothing is purchasable. Either wire RevenueCat in
  the app or drop the paid tier.
- **Publish the store listing.** Upload the feature graphic, screenshots and paste-ready submission
  sheet from `mobile/store/listing.md` to Play Console. It follows the Console order: main listing,
  store settings, app content declarations (content rating, target audience, data safety, account
  deletion, health apps), pricing, release and the force-update setting.
- **Set the force-update floor after release.** Keep `MIN_APP_VERSION=1.0.0` until `1.0.5` is at
  100% rollout, then raise it only when an old build must be retired.

## Next

- **Continuous integration.** Add a workflow that runs `make web`, `go vet ./...` and `go test ./...`,
  with a Postgres service so the store integration tests do not skip. Today the store SQL is only
  exercised when a developer sets `TEST_DATABASE_URL` by hand.
- **RevenueCat entitlement refresh fallback.** Implement the backend template's task 5: when a
  user's entitlement row is stale, fetch it from the RevenueCat REST API with a short cache. Without
  it, a lost webhook leaves a paying user on free limits until the next event.
- **Apply `TRANSFER` events.** They are recorded but not applied, so a subscription transferred
  between app user ids does not move to the new account.

## Later — cleanup and reuse

- **Tidy dead code:** `Store.Pool()`, and `CreateOrGetUser`/`UpsertEntitlement` (test-only, one still
  on the `httpapi.Store` interface).
- **Add an iOS store URL for force update.** The gate currently returns one Play Store URL; an iOS
  build needs a per-platform URL before shipping.
- **Prepare the Litpace backend:** copy this template (keep auth, entitlements, limits and ops;
  replace the tracker's AI endpoints with TTS + timestamp alignment and per-document audio caching).
  Do not edit this repo while doing it (`AGENTS.md`).

## Also worth deciding

- **Shared rate-limit / spend state.** Rate limiting and the spend cap are process-local; fine for a
  single VPS, but a second instance would not share counters.
