-- +goose Up
-- Stable Google identity for an account. The subject claim ("sub") is the only
-- Google-provided value we keep: no email, name or picture. It is nullable so
-- anonymous accounts stay valid, and Postgres allows many NULLs under a unique
-- index, so only accounts that actually signed in with Google are constrained.
ALTER TABLE users ADD COLUMN google_sub text;

CREATE UNIQUE INDEX users_google_sub_key ON users (google_sub);

-- +goose Down
DROP INDEX users_google_sub_key;
ALTER TABLE users DROP COLUMN google_sub;
