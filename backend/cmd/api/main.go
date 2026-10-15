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

	"github.com/tedif/weight-buddy-backend/internal/config"
	httpapi "github.com/tedif/weight-buddy-backend/internal/http"
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

	ln, err := net.Listen("tcp", cfg.HTTPAddr)
	if err != nil {
		return fmt.Errorf("listen on %s: %w", cfg.HTTPAddr, err)
	}

	router := httpapi.NewRouter(httpapi.Deps{
		Logger:         logger,
		RequestTimeout: cfg.RequestTimeout,
	})
	srv := httpapi.NewServer(router, logger)

	logger.Info("starting api", "env", cfg.Env, "addr", ln.Addr().String())
	return httpapi.Run(ctx, srv, ln, logger, cfg.ShutdownTimeout)
}

func newLogger(cfg config.Config) *slog.Logger {
	opts := &slog.HandlerOptions{Level: cfg.LogLevel}
	if cfg.IsProduction() {
		return slog.New(slog.NewJSONHandler(os.Stdout, opts))
	}
	return slog.New(slog.NewTextHandler(os.Stdout, opts))
}
