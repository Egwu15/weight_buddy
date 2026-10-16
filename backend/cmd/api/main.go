// Command api runs the HTTP service.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"net"
	"os"
	"os/signal"
	"syscall"

	"github.com/tedif/weight-buddy-backend/internal/ai"
	"github.com/tedif/weight-buddy-backend/internal/auth"
	"github.com/tedif/weight-buddy-backend/internal/config"
	httpapi "github.com/tedif/weight-buddy-backend/internal/http"
	"github.com/tedif/weight-buddy-backend/internal/limits"
	"github.com/tedif/weight-buddy-backend/internal/site"
	"github.com/tedif/weight-buddy-backend/internal/store"
)

func main() {
	// Install a structured logger before anything else so that a config or
	// startup failure is always reported as JSON, even though the real log
	// level and format are only known once config has loaded.
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stderr, nil)))

	if err := run(); err != nil {
		slog.Error("service exited with error", "err", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	logger := newLogger(cfg)
	slog.SetDefault(logger)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	db, err := store.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer db.Close()

	if cfg.OpenAIAPIKey == "" {
		logger.Warn("OPENAI_API_KEY is not set; AI routes will return 503")
	}
	if cfg.RevenueCatWebhookSecret == "" {
		logger.Warn("REVENUECAT_WEBHOOK_SECRET is not set; the webhook route will return 503")
	}

	provider := newProvider(cfg)
	enforcer := &limits.Enforcer{
		Store:    db,
		Config:   limits.Default(),
		SpendCap: cfg.DailySpendCapUSD,
	}

	googleVerifier, err := auth.NewGoogleVerifier(ctx, cfg.GoogleWebClientID)
	if err != nil {
		return err
	}

	ln, err := net.Listen("tcp", cfg.HTTPAddr)
	if err != nil {
		return fmt.Errorf("listen on %s: %w", cfg.HTTPAddr, err)
	}

	router := httpapi.NewRouter(httpapi.Deps{
		Logger:                    logger,
		RequestTimeout:            cfg.RequestTimeout,
		Store:                     db,
		Tokens:                    auth.NewTokens(cfg.JWTSecret, cfg.JWTTTL),
		GoogleVerifier:            googleVerifier,
		JWTSecret:                 cfg.JWTSecret,
		FreeAccountsPerDevice:     cfg.FreeAccountsPerDevice,
		RevenueCatWebhookSecret:   cfg.RevenueCatWebhookSecret,
		RevenueCatEntitlementID:   cfg.RevenueCatEntitlementID,
		Site:                      site.Handler(),
		Limits:                    enforcer,
		Provider:                  provider,
		RateLimitPerIPPerMinute:   cfg.RateLimitPerIPPerMinute,
		RateLimitPerUserPerMinute: cfg.RateLimitPerUserPerMinute,
		TrustedProxies:            cfg.TrustedProxies,
	})
	srv := httpapi.NewServer(router, logger)

	logger.Info("starting api", "env", cfg.Env, "addr", ln.Addr().String())
	return httpapi.Run(ctx, srv, ln, logger, cfg.ShutdownTimeout)
}

// newProvider builds the AI provider, or returns nil when no key is configured
// so the AI routes answer 503 instead of failing every call at the provider.
func newProvider(cfg config.Config) ai.Provider {
	if cfg.OpenAIAPIKey == "" {
		return nil
	}
	return ai.NewOpenAIProvider(ai.OpenAIConfig{
		APIKey:          cfg.OpenAIAPIKey,
		BaseURL:         cfg.OpenAIBaseURL,
		ParseModel:      cfg.ParseModel,
		TranscribeModel: cfg.TranscribeModel,
		Timeout:         cfg.AITimeout,
	})
}

func newLogger(cfg config.Config) *slog.Logger {
	opts := &slog.HandlerOptions{Level: cfg.LogLevel}
	if cfg.IsProduction() {
		return slog.New(slog.NewJSONHandler(os.Stdout, opts))
	}
	return slog.New(slog.NewTextHandler(os.Stdout, opts))
}
