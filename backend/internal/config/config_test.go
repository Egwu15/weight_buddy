package config

import (
	"log/slog"
	"net/netip"
	"reflect"
	"strings"
	"testing"
	"time"
)

func mapLookup(env map[string]string) envLookup {
	return func(key string) (string, bool) {
		v, ok := env[key]
		return v, ok
	}
}

// withRequired layers the env vars every valid config needs on top of a case.
func withRequired(env map[string]string) map[string]string {
	out := map[string]string{
		"DATABASE_URL":         "postgres://user@localhost:5432/db",
		"JWT_SECRET":           "test-secret",
		"GOOGLE_WEB_CLIENT_ID": "test-client.apps.googleusercontent.com",
	}
	for k, v := range env {
		out[k] = v
	}
	return out
}

func TestLoad(t *testing.T) {
	tests := []struct {
		name    string
		env     map[string]string
		want    Config
		wantErr string
	}{
		{
			name: "defaults",
			env:  withRequired(nil),
			want: Config{
				Env:                       "development",
				HTTPAddr:                  ":8080",
				LogLevel:                  slog.LevelInfo,
				ShutdownTimeout:           10 * time.Second,
				RequestTimeout:            60 * time.Second,
				DatabaseURL:               "postgres://user@localhost:5432/db",
				JWTSecret:                 "test-secret",
				JWTTTL:                    720 * time.Hour,
				FreeAccountsPerDevice:     1,
				RateLimitPerIPPerMinute:   60,
				RateLimitPerUserPerMinute: 30,
				DailySpendCapUSD:          25,
				OpenAIBaseURL:             "https://api.openai.com/v1",
				ParseModel:                "gpt-4o-mini",
				TranscribeModel:           "gpt-transcribe",
				AITimeout:                 90 * time.Second,
				RevenueCatEntitlementID:   "pro",
				GoogleWebClientID:         "test-client.apps.googleusercontent.com",
				TrustedProxies:            defaultTrustedProxies(),
			},
		},
		{
			name: "explicit values",
			env: withRequired(map[string]string{
				"APP_ENV":                    "production",
				"HTTP_ADDR":                  "127.0.0.1:9000",
				"LOG_LEVEL":                  "debug",
				"SHUTDOWN_TIMEOUT":           "30s",
				"REQUEST_TIMEOUT":            "15s",
				"JWT_TTL":                    "1h",
				"FREE_ACCOUNTS_PER_DEVICE":   "3",
				"RATE_LIMIT_IP_PER_MINUTE":   "120",
				"RATE_LIMIT_USER_PER_MINUTE": "40",
				"DAILY_SPEND_CAP_USD":        "100",
				"OPENAI_API_KEY":             "sk-test",
				"OPENAI_BASE_URL":            "https://example.test/v1/",
				"PARSE_MODEL":                "gpt-4o",
				"TRANSCRIBE_MODEL":           "whisper-1",
				"AI_TIMEOUT":                 "45s",
				"REVENUECAT_WEBHOOK_SECRET":  "whsec",
				"REVENUECAT_ENTITLEMENT":     "premium",
				"TRUSTED_PROXIES":            "10.0.0.0/8, 192.168.1.5",
			}),
			want: Config{
				Env:                       "production",
				HTTPAddr:                  "127.0.0.1:9000",
				LogLevel:                  slog.LevelDebug,
				ShutdownTimeout:           30 * time.Second,
				RequestTimeout:            15 * time.Second,
				DatabaseURL:               "postgres://user@localhost:5432/db",
				JWTSecret:                 "test-secret",
				JWTTTL:                    time.Hour,
				FreeAccountsPerDevice:     3,
				RateLimitPerIPPerMinute:   120,
				RateLimitPerUserPerMinute: 40,
				DailySpendCapUSD:          100,
				OpenAIAPIKey:              "sk-test",
				OpenAIBaseURL:             "https://example.test/v1",
				ParseModel:                "gpt-4o",
				TranscribeModel:           "whisper-1",
				AITimeout:                 45 * time.Second,
				RevenueCatWebhookSecret:   "whsec",
				RevenueCatEntitlementID:   "premium",
				GoogleWebClientID:         "test-client.apps.googleusercontent.com",
				TrustedProxies: []netip.Prefix{
					netip.MustParsePrefix("10.0.0.0/8"),
					netip.MustParsePrefix("192.168.1.5/32"),
				},
			},
		},
		{
			name: "http addr is trimmed",
			env:  withRequired(map[string]string{"HTTP_ADDR": "  127.0.0.1:9000  "}),
			want: Config{
				Env:                       "development",
				HTTPAddr:                  "127.0.0.1:9000",
				LogLevel:                  slog.LevelInfo,
				ShutdownTimeout:           10 * time.Second,
				RequestTimeout:            60 * time.Second,
				DatabaseURL:               "postgres://user@localhost:5432/db",
				JWTSecret:                 "test-secret",
				JWTTTL:                    720 * time.Hour,
				FreeAccountsPerDevice:     1,
				RateLimitPerIPPerMinute:   60,
				RateLimitPerUserPerMinute: 30,
				DailySpendCapUSD:          25,
				OpenAIBaseURL:             "https://api.openai.com/v1",
				ParseModel:                "gpt-4o-mini",
				TranscribeModel:           "gpt-transcribe",
				AITimeout:                 90 * time.Second,
				RevenueCatEntitlementID:   "pro",
				GoogleWebClientID:         "test-client.apps.googleusercontent.com",
				TrustedProxies:            defaultTrustedProxies(),
			},
		},
		{
			name:    "invalid env",
			env:     withRequired(map[string]string{"APP_ENV": "staging"}),
			wantErr: "APP_ENV",
		},
		{
			name:    "missing database url",
			env:     map[string]string{"JWT_SECRET": "s"},
			wantErr: "DATABASE_URL is required",
		},
		{
			name:    "missing jwt secret",
			env:     map[string]string{"DATABASE_URL": "postgres://x"},
			wantErr: "JWT_SECRET is required",
		},
		{
			name:    "missing google web client id",
			env:     withRequired(map[string]string{"GOOGLE_WEB_CLIENT_ID": ""}),
			wantErr: "GOOGLE_WEB_CLIENT_ID is required",
		},
		{
			name:    "invalid log level",
			env:     withRequired(map[string]string{"LOG_LEVEL": "verbose"}),
			wantErr: "LOG_LEVEL",
		},
		{
			name:    "addr without port",
			env:     withRequired(map[string]string{"HTTP_ADDR": "8080"}),
			wantErr: "HTTP_ADDR must be a host:port address",
		},
		{
			name:    "non-positive shutdown timeout",
			env:     withRequired(map[string]string{"SHUTDOWN_TIMEOUT": "0s"}),
			wantErr: "SHUTDOWN_TIMEOUT must be positive",
		},
		{
			name:    "unparsable shutdown timeout",
			env:     withRequired(map[string]string{"SHUTDOWN_TIMEOUT": "soon"}),
			wantErr: "not a valid duration",
		},
		{
			name:    "non-positive request timeout",
			env:     withRequired(map[string]string{"REQUEST_TIMEOUT": "-5s"}),
			wantErr: "REQUEST_TIMEOUT must be positive",
		},
		{
			name:    "invalid rate limit",
			env:     withRequired(map[string]string{"RATE_LIMIT_IP_PER_MINUTE": "lots"}),
			wantErr: "RATE_LIMIT_IP_PER_MINUTE",
		},
		{
			name:    "invalid spend cap",
			env:     withRequired(map[string]string{"DAILY_SPEND_CAP_USD": "cheap"}),
			wantErr: "DAILY_SPEND_CAP_USD",
		},
		{
			name:    "empty http addr",
			env:     withRequired(map[string]string{"HTTP_ADDR": "  "}),
			wantErr: "HTTP_ADDR must not be empty",
		},
		{
			name:    "invalid trusted proxies",
			env:     withRequired(map[string]string{"TRUSTED_PROXIES": "not-an-ip"}),
			wantErr: "TRUSTED_PROXIES",
		},
		{
			name: "multiple errors are joined",
			env: withRequired(map[string]string{
				"APP_ENV":   "staging",
				"LOG_LEVEL": "verbose",
			}),
			wantErr: "APP_ENV",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := load(mapLookup(tt.env))

			if tt.wantErr != "" {
				if err == nil {
					t.Fatalf("expected error containing %q, got nil", tt.wantErr)
				}
				if !strings.Contains(err.Error(), tt.wantErr) {
					t.Fatalf("expected error containing %q, got %q", tt.wantErr, err.Error())
				}
				if tt.name == "multiple errors are joined" && !strings.Contains(err.Error(), "LOG_LEVEL") {
					t.Fatalf("expected joined error to also mention LOG_LEVEL, got %q", err.Error())
				}
				return
			}

			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Fatalf("got %+v, want %+v", got, tt.want)
			}
		})
	}
}

func TestIsProduction(t *testing.T) {
	if !(Config{Env: "production"}).IsProduction() {
		t.Fatal("expected production env to report IsProduction")
	}
	if (Config{Env: "development"}).IsProduction() {
		t.Fatal("expected development env to report !IsProduction")
	}
}
