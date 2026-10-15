# Weight Buddy backend build and run helpers.
BINARY := weight-buddy
MIGRATE := weight-buddy-migrate

.PHONY: build test vet fmt run migrate migrate-status tidy

build:
	go build -o bin/$(BINARY) ./cmd/api
	go build -o bin/$(MIGRATE) ./cmd/migrate

test:
	go test ./...

vet:
	go vet ./...

fmt:
	gofmt -w .

tidy:
	go mod tidy

# Run the API locally. Reads configuration from the environment (see
# .env.example); DATABASE_URL and JWT_SECRET are required.
run:
	go run ./cmd/api

# Apply migrations. Requires DATABASE_URL in the environment.
migrate:
	go run ./cmd/migrate up

migrate-status:
	go run ./cmd/migrate status
