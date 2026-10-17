# Roadmap

Planned and outstanding work, in rough order. This is where "what next" lives so `HANDOFF.md` can
stay short and disposable. Status details and rationale are in `main.md` (§10) and `journal.md`;
this file only sequences the work.

## Now — before shipping

- **Review the legal copy.** The privacy policy, terms and deletion page are drafts; have them
  reviewed by a qualified person before publishing. The privacy and deletion URLs go into the Play
  Console listing and the Data safety form.
- **Decide on subscriptions.** The backend already models a paid entitlement, but the app ships no
  purchase SDK (the RevenueCat seam is a no-op), so nothing is purchasable. Either wire RevenueCat in
  the app or drop the paid tier.

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
- **Replace the home page screenshot placeholders** with real captures.
- **Prepare the Litpace backend:** copy this template (keep auth, entitlements, limits and ops;
  replace the tracker's AI endpoints with TTS + timestamp alignment and per-document audio caching).
  Do not edit this repo while doing it (`AGENTS.md`).

## Also worth deciding

- **Shared rate-limit / spend state.** Rate limiting and the spend cap are process-local; fine for a
  single VPS, but a second instance would not share counters.
