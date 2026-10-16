# Weight Buddy backend build and run helpers.
BINARY := weight-buddy
MIGRATE := weight-buddy-migrate

.PHONY: build web test vet fmt run migrate migrate-status tidy

# Build the embedded public site. Its output (web/dist) is required by the Go
# build: //go:embed fails clearly if it is missing. Dependencies are installed
# only when node_modules is absent, so this stays cheap on repeated runs.
web:
	cd web && { [ -d node_modules ] || npm ci; } && npm run build

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
