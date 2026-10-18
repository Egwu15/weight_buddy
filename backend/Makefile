# Weight Buddy backend build and run helpers.
BINARY := weight-buddy
MIGRATE := weight-buddy-migrate

.PHONY: build web test vet fmt run migrate migrate-status tidy docker docker-up docker-down docker-reset legal-snapshot

# Build the embedded public site. Its output (web/dist) is required by the Go
# build: //go:embed fails clearly if it is missing. Dependencies are installed
# only when node_modules is absent, so this stays cheap on repeated runs.
# SITE_STRICT_PLACEHOLDERS=1 makes the build fail if any {{PLACEHOLDER}} is left
# in web/src/config.ts, so nothing ships unnoticed.
web:
	cd web && { [ -d node_modules ] || npm ci; } && SITE_STRICT_PLACEHOLDERS=1 npm run build

# Freeze the current privacy policy and terms into immutable archived copies
# under web/public/legal/archive/. Run this BEFORE editing the legal copy, then
# add the date to config.legalArchive. Optionally pass DATE=YYYY-MM-DD (defaults
# to today). See web/scripts/snapshot-legal.mjs .
legal-snapshot: web
	node web/scripts/snapshot-legal.mjs $(DATE)

# build/test/vet/run all compile the module-root webassets package, which
# embeds web/dist, so they depend on `web`.
build: web
	go build -o bin/$(BINARY) ./cmd/api
	go build -o bin/$(MIGRATE) ./cmd/migrate

test: web
	go test ./...

vet: web
	go vet ./...

fmt:
	gofmt -w .

tidy:
	go mod tidy

# Run the API locally. Reads configuration from the environment (see
# .env.example); DATABASE_URL and JWT_SECRET are required.
run: web
	go run ./cmd/api

# Apply migrations. Requires DATABASE_URL in the environment.
migrate:
	go run ./cmd/migrate up

migrate-status:
	go run ./cmd/migrate status

# Build the container image. Multi-stage: the site and both static binaries are
# built inside the image; the runtime is distroless. See Dockerfile .
docker:
	docker build -t $(BINARY):latest .

# Run the whole backend (Postgres + migrate + api) with one command.
docker-up:
	docker compose up --build

# Stop the stack, keeping the database volume.
docker-down:
	docker compose down

# Stop the stack AND delete the database volume (Postgres data is lost).
docker-reset:
	docker compose down -v
