-- +goose Up
-- Deleting an account removes its revenuecat_events rows by matching the app
-- user id inside the stored payload (see Store.DeleteUser). Without these the
-- lookup is a sequential scan of the whole, ever-growing event history. The
-- scalar paths get btree expression indexes (equality); the array paths get GIN
-- indexes so the jsonb `?` membership test is indexed too.
CREATE INDEX revenuecat_events_app_user_id_idx
    ON revenuecat_events ((payload->'event'->>'app_user_id'));

CREATE INDEX revenuecat_events_original_app_user_id_idx
    ON revenuecat_events ((payload->'event'->>'original_app_user_id'));

CREATE INDEX revenuecat_events_aliases_idx
    ON revenuecat_events USING gin ((payload->'event'->'aliases'));

CREATE INDEX revenuecat_events_transferred_from_idx
    ON revenuecat_events USING gin ((payload->'event'->'transferred_from'));

CREATE INDEX revenuecat_events_transferred_to_idx
    ON revenuecat_events USING gin ((payload->'event'->'transferred_to'));

-- +goose Down
DROP INDEX revenuecat_events_transferred_to_idx;
DROP INDEX revenuecat_events_transferred_from_idx;
DROP INDEX revenuecat_events_aliases_idx;
DROP INDEX revenuecat_events_original_app_user_id_idx;
DROP INDEX revenuecat_events_app_user_id_idx;
