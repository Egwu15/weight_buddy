// Command api runs the HTTP service.
package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/tedif/weight-buddy-backend/internal/config"
	httpapi "github.com/tedif/weight-buddy-backend/internal/http"
)

func main() {
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

	router := httpapi.NewRouter(httpapi.Deps{Logger: logger})
	srv := httpapi.NewServer(cfg.HTTPAddr, router, logger)

	logger.Info("starting api", "env", cfg.Env, "addr", cfg.HTTPAddr)
	return httpapi.Run(ctx, srv, logger, cfg.ShutdownTimeout)
}

func newLogger(cfg config.Config) *slog.Logger {
	opts := &slog.HandlerOptions{Level: cfg.LogLevel}
	if cfg.IsProduction() {
		return slog.New(slog.NewJSONHandler(os.Stdout, opts))
	}
	return slog.New(slog.NewTextHandler(os.Stdout, opts))
}
