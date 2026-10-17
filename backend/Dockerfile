# syntax=docker/dockerfile:1

# Multi-stage build for the Weight Buddy backend. The runtime image holds only
# the two static binaries: the Go build embeds the pre-rendered site and the
# SQL migrations, so nothing else ships.
#
#   docker build -t weight-buddy .
#   # Migrate first, then serve. Running the API against an unmigrated database
#   # still reports /healthz 200, but every request fails on missing tables.
#   docker run --rm -e DATABASE_URL=... weight-buddy /app/weight-buddy-migrate up
#   docker run --rm -e DATABASE_URL=... -e JWT_SECRET=... -e GOOGLE_WEB_CLIENT_ID=... -p 8080:8080 weight-buddy
#
# The site build fails if any {{PLACEHOLDER}} is left in web/src/config.ts
# (SITE_STRICT_PLACEHOLDERS=1); override the arg to build a template as-is.
#
# Base images are pinned by digest so a rebuild of unchanged source produces the
# same bytes; bump the digest deliberately when upgrading.

# --- Stage 1: build the public website (Vite + prerender) -------------------
FROM node:22-alpine@sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402 AS web
WORKDIR /web
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web/ ./
ARG SITE_STRICT_PLACEHOLDERS=1
ENV SITE_STRICT_PLACEHOLDERS=${SITE_STRICT_PLACEHOLDERS}
RUN npm run build

# --- Stage 2: build the Go binaries -----------------------------------------
FROM golang:1.27-alpine@sha256:f92b6ef800e499660581efdabdf25d9d817a9d124eaf900924f0504e7e27e12d AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
COPY --from=web /web/dist ./web/dist
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/weight-buddy ./cmd/api && \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/weight-buddy-migrate ./cmd/migrate

# --- Stage 3: minimal runtime ----------------------------------------------
# distroless static ships CA certificates (outbound TLS to OpenAI, Google and
# RevenueCat) and a nonroot user; it has no shell, which is the point.
FROM gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab
WORKDIR /app
COPY --chown=65532:65532 --from=build /out/weight-buddy /app/weight-buddy
COPY --chown=65532:65532 --from=build /out/weight-buddy-migrate /app/weight-buddy-migrate
EXPOSE 8080
ENTRYPOINT ["/app/weight-buddy"]
