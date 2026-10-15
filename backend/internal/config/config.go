// Package config loads and validates all runtime configuration from
// environment variables. Nothing in this service reads configuration from
// anywhere else, so a process either starts with a fully valid config or it
// refuses to start.
package config

import (
	"errors"
	"fmt"
	"log/slog"
	"os"
	"strings"
	"time"
)

// Defaults applied when the corresponding environment variable is unset.
const (
	defaultEnv             = "development"
	defaultHTTPAddr        = ":8080"
	defaultLogLevel        = "info"
	defaultShutdownTimeout = 10 * time.Second
)

// Config is the fully resolved, validated runtime configuration.
type Config struct {
	Env             string
	HTTPAddr        string
	LogLevel        slog.Level
	ShutdownTimeout time.Duration
}

// IsProduction reports whether the service is running in production mode.
func (c Config) IsProduction() bool {
	return c.Env == "production"
}

// envLookup resolves an environment variable. It mirrors os.LookupEnv so tests
// can supply their own lookup without touching the real process environment.
type envLookup func(key string) (string, bool)

// Load reads configuration from the process environment and validates it.
func Load() (Config, error) {
	return load(os.LookupEnv)
}

func load(lookup envLookup) (Config, error) {
	cfg := Config{
		Env:             getEnv(lookup, "APP_ENV", defaultEnv),
		HTTPAddr:        getEnv(lookup, "HTTP_ADDR", defaultHTTPAddr),
		ShutdownTimeout: defaultShutdownTimeout,
	}

	var errs []error

	switch cfg.Env {
	case "development", "production":
	default:
		errs = append(errs, fmt.Errorf("APP_ENV must be %q or %q, got %q", "development", "production", cfg.Env))
	}

	if raw, ok := lookup("SHUTDOWN_TIMEOUT"); ok && raw != "" {
		d, err := time.ParseDuration(raw)
		switch {
		case err != nil:
			errs = append(errs, fmt.Errorf("SHUTDOWN_TIMEOUT is not a valid duration: %w", err))
		case d <= 0:
			errs = append(errs, fmt.Errorf("SHUTDOWN_TIMEOUT must be positive, got %q", raw))
		default:
			cfg.ShutdownTimeout = d
		}
	}

	level, err := parseLogLevel(getEnv(lookup, "LOG_LEVEL", defaultLogLevel))
	if err != nil {
		errs = append(errs, err)
	}
	cfg.LogLevel = level

	if strings.TrimSpace(cfg.HTTPAddr) == "" {
		errs = append(errs, errors.New("HTTP_ADDR must not be empty"))
	}

	if len(errs) > 0 {
		return Config{}, errors.Join(errs...)
	}
	return cfg, nil
}

func parseLogLevel(raw string) (slog.Level, error) {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "debug":
		return slog.LevelDebug, nil
	case "", "info":
		return slog.LevelInfo, nil
	case "warn", "warning":
		return slog.LevelWarn, nil
	case "error":
		return slog.LevelError, nil
	default:
		return slog.LevelInfo, fmt.Errorf("LOG_LEVEL must be one of debug, info, warn, error, got %q", raw)
	}
}

func getEnv(lookup envLookup, key, fallback string) string {
	if v, ok := lookup(key); ok {
		return v
	}
	return fallback
}
