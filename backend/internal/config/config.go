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
	"net/netip"
	"os"
	"strconv"
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
	defaultJWTTTL          = 720 * time.Hour
	defaultAITimeout       = 90 * time.Second

	defaultFreeAccountsPerDevice = 1
	defaultRateLimitIP           = 60
	defaultRateLimitUser         = 30
	defaultDailySpendCapUSD      = 25.0

	defaultParseModel      = "gpt-4o-mini"
	defaultTranscribeModel = "gpt-transcribe"
	defaultOpenAIBaseURL   = "https://api.openai.com/v1"

	defaultRevenueCatEntitleID = "pro"
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

	// DatabaseURL is the Postgres connection string. Required.
	DatabaseURL string
	// JWTSecret signs app session tokens (HS256). Required.
	JWTSecret string
	// JWTTTL is how long an issued app session token stays valid.
	JWTTTL time.Duration

	// FreeAccountsPerDevice caps how many anonymous free accounts a single
	// device (hashed client IP) may create per day.
	FreeAccountsPerDevice int
	// Rate limits are requests per minute, per IP and per authenticated user.
	RateLimitPerIPPerMinute   int
	RateLimitPerUserPerMinute int
	// TrustedProxies are the networks whose X-Forwarded-For headers the
	// service trusts when resolving the client IP (Caddy on loopback by
	// default). Without this, a client could spoof its address.
	TrustedProxies []netip.Prefix
	// DailySpendCapUSD is the global AI spend cap; once today's estimate
	// reaches it the proxy returns a friendly 503.
	DailySpendCapUSD float64

	// AI provider settings. OpenAIAPIKey is the provider key held by the
	// backend only; the app never sees it.
	OpenAIAPIKey    string
	OpenAIBaseURL   string
	ParseModel      string
	TranscribeModel string
	AITimeout       time.Duration

	// RevenueCat settings. The webhook secret is compared in constant time.
	RevenueCatWebhookSecret string
	RevenueCatEntitlementID string
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

	cfg.DatabaseURL = strings.TrimSpace(getEnv(lookup, "DATABASE_URL", ""))
	if cfg.DatabaseURL == "" {
		errs = append(errs, errors.New("DATABASE_URL is required"))
	}

	cfg.JWTSecret = getEnv(lookup, "JWT_SECRET", "")
	if strings.TrimSpace(cfg.JWTSecret) == "" {
		errs = append(errs, errors.New("JWT_SECRET is required"))
	}

	if d, err := parsePositiveDuration(lookup, "JWT_TTL", defaultJWTTTL); err != nil {
		errs = append(errs, err)
	} else {
		cfg.JWTTTL = d
	}

	if n, err := parsePositiveInt(lookup, "FREE_ACCOUNTS_PER_DEVICE", defaultFreeAccountsPerDevice); err != nil {
		errs = append(errs, err)
	} else {
		cfg.FreeAccountsPerDevice = n
	}

	if n, err := parsePositiveInt(lookup, "RATE_LIMIT_IP_PER_MINUTE", defaultRateLimitIP); err != nil {
		errs = append(errs, err)
	} else {
		cfg.RateLimitPerIPPerMinute = n
	}

	if n, err := parsePositiveInt(lookup, "RATE_LIMIT_USER_PER_MINUTE", defaultRateLimitUser); err != nil {
		errs = append(errs, err)
	} else {
		cfg.RateLimitPerUserPerMinute = n
	}

	if n, err := parsePositiveFloat(lookup, "DAILY_SPEND_CAP_USD", defaultDailySpendCapUSD); err != nil {
		errs = append(errs, err)
	} else {
		cfg.DailySpendCapUSD = n
	}

	trusted, err := parseTrustedProxies(lookup)
	if err != nil {
		errs = append(errs, err)
	} else {
		cfg.TrustedProxies = trusted
	}

	cfg.OpenAIAPIKey = getEnv(lookup, "OPENAI_API_KEY", "")
	cfg.OpenAIBaseURL = strings.TrimRight(getEnv(lookup, "OPENAI_BASE_URL", defaultOpenAIBaseURL), "/")
	cfg.ParseModel = getEnv(lookup, "PARSE_MODEL", defaultParseModel)
	cfg.TranscribeModel = getEnv(lookup, "TRANSCRIBE_MODEL", defaultTranscribeModel)

	if d, err := parsePositiveDuration(lookup, "AI_TIMEOUT", defaultAITimeout); err != nil {
		errs = append(errs, err)
	} else {
		cfg.AITimeout = d
	}

	cfg.RevenueCatWebhookSecret = getEnv(lookup, "REVENUECAT_WEBHOOK_SECRET", "")
	cfg.RevenueCatEntitlementID = getEnv(lookup, "REVENUECAT_ENTITLEMENT", defaultRevenueCatEntitleID)

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

func parsePositiveInt(lookup envLookup, key string, fallback int) (int, error) {
	raw, ok := lookup(key)
	if !ok || raw == "" {
		return fallback, nil
	}
	n, err := strconv.Atoi(strings.TrimSpace(raw))
	if err != nil {
		return fallback, fmt.Errorf("%s is not a valid integer: %w", key, err)
	}
	if n <= 0 {
		return fallback, fmt.Errorf("%s must be positive, got %q", key, raw)
	}
	return n, nil
}

func parsePositiveFloat(lookup envLookup, key string, fallback float64) (float64, error) {
	raw, ok := lookup(key)
	if !ok || raw == "" {
		return fallback, nil
	}
	f, err := strconv.ParseFloat(strings.TrimSpace(raw), 64)
	if err != nil {
		return fallback, fmt.Errorf("%s is not a valid number: %w", key, err)
	}
	if f <= 0 {
		return fallback, fmt.Errorf("%s must be positive, got %q", key, raw)
	}
	return f, nil
}

// defaultTrustedProxies is the loopback set, matching Caddy running on the
// same host.
func defaultTrustedProxies() []netip.Prefix {
	return []netip.Prefix{
		netip.MustParsePrefix("127.0.0.1/32"),
		netip.MustParsePrefix("::1/128"),
	}
}

// parseTrustedProxies reads TRUSTED_PROXIES: a comma-separated list of CIDRs or
// bare IPs whose forwarded headers are trusted. Unset means loopback; the
// literal "none" means trust nothing.
func parseTrustedProxies(lookup envLookup) ([]netip.Prefix, error) {
	raw, ok := lookup("TRUSTED_PROXIES")
	if !ok || strings.TrimSpace(raw) == "" {
		return defaultTrustedProxies(), nil
	}
	if strings.EqualFold(strings.TrimSpace(raw), "none") {
		return nil, nil
	}

	var prefixes []netip.Prefix
	for _, part := range strings.Split(raw, ",") {
		token := strings.TrimSpace(part)
		if token == "" {
			continue
		}
		if prefix, err := netip.ParsePrefix(token); err == nil {
			prefixes = append(prefixes, prefix.Masked())
			continue
		}
		addr, err := netip.ParseAddr(token)
		if err != nil {
			return nil, fmt.Errorf("TRUSTED_PROXIES entry %q is not an IP or CIDR", token)
		}
		unmapped := addr.Unmap()
		prefixes = append(prefixes, netip.PrefixFrom(unmapped, unmapped.BitLen()))
	}
	return prefixes, nil
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
