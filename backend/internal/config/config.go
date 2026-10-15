// Package config loads and validates all runtime configuration from
// environment variables. Nothing in this service reads configuration from
// anywhere else, so a process either starts with a fully valid config or it
// refuses to start.
package config

import (
	"errors"
	"fmt"
	"log/slog"
	"net"
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
	defaultRequestTimeout  = 60 * time.Second
)

// Config is the fully resolved, validated runtime configuration.
type Config struct {
	Env             string
	HTTPAddr        string
	LogLevel        slog.Level
	ShutdownTimeout time.Duration
	// RequestTimeout bounds how long a single request handler may run. It is
	// applied per request rather than as a global server WriteTimeout so that
	// long AI calls and audio uploads are not cut off by a value chosen for
	// the fastest endpoint.
	RequestTimeout time.Duration
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
		Env:      getEnv(lookup, "APP_ENV", defaultEnv),
		HTTPAddr: strings.TrimSpace(getEnv(lookup, "HTTP_ADDR", defaultHTTPAddr)),
	}

	var errs []error

	switch cfg.Env {
	case "development", "production":
	default:
		errs = append(errs, fmt.Errorf("APP_ENV must be %q or %q, got %q", "development", "production", cfg.Env))
	}

	if err := validateAddr(cfg.HTTPAddr); err != nil {
		errs = append(errs, err)
	}

	level, levelErr := parseLogLevel(getEnv(lookup, "LOG_LEVEL", defaultLogLevel))
	if levelErr != nil {
		errs = append(errs, levelErr)
	} else {
		cfg.LogLevel = level
	}

	shutdownTimeout, err := parsePositiveDuration(lookup, "SHUTDOWN_TIMEOUT", defaultShutdownTimeout)
	if err != nil {
		errs = append(errs, err)
	} else {
		cfg.ShutdownTimeout = shutdownTimeout
	}

	requestTimeout, err := parsePositiveDuration(lookup, "REQUEST_TIMEOUT", defaultRequestTimeout)
	if err != nil {
		errs = append(errs, err)
	} else {
		cfg.RequestTimeout = requestTimeout
	}

	if len(errs) > 0 {
		return Config{}, errors.Join(errs...)
	}
	return cfg, nil
}

func validateAddr(addr string) error {
	if addr == "" {
		return errors.New("HTTP_ADDR must not be empty")
	}
	if _, _, err := net.SplitHostPort(addr); err != nil {
		return fmt.Errorf("HTTP_ADDR must be a host:port address: %w", err)
	}
	return nil
}

func parsePositiveDuration(lookup envLookup, key string, fallback time.Duration) (time.Duration, error) {
	raw, ok := lookup(key)
	if !ok || raw == "" {
		return fallback, nil
	}
	d, err := time.ParseDuration(raw)
	if err != nil {
		return fallback, fmt.Errorf("%s is not a valid duration: %w", key, err)
	}
	if d <= 0 {
		return fallback, fmt.Errorf("%s must be positive, got %q", key, raw)
	}
	return d, nil
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
