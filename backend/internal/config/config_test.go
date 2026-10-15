package config

import (
	"log/slog"
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

func TestLoad(t *testing.T) {
	tests := []struct {
		name    string
		env     map[string]string
		want    Config
		wantErr string
	}{
		{
			name: "defaults",
			env:  map[string]string{},
			want: Config{
				Env:             "development",
				HTTPAddr:        ":8080",
				LogLevel:        slog.LevelInfo,
				ShutdownTimeout: 10 * time.Second,
				RequestTimeout:  60 * time.Second,
			},
		},
		{
			name: "explicit values",
			env: map[string]string{
				"APP_ENV":          "production",
				"HTTP_ADDR":        "127.0.0.1:9000",
				"LOG_LEVEL":        "debug",
				"SHUTDOWN_TIMEOUT": "30s",
				"REQUEST_TIMEOUT":  "15s",
			},
			want: Config{
				Env:             "production",
				HTTPAddr:        "127.0.0.1:9000",
				LogLevel:        slog.LevelDebug,
				ShutdownTimeout: 30 * time.Second,
				RequestTimeout:  15 * time.Second,
			},
		},
		{
			name: "http addr is trimmed",
			env:  map[string]string{"HTTP_ADDR": "  127.0.0.1:9000  "},
			want: Config{
				Env:             "development",
				HTTPAddr:        "127.0.0.1:9000",
				LogLevel:        slog.LevelInfo,
				ShutdownTimeout: 10 * time.Second,
				RequestTimeout:  60 * time.Second,
			},
		},
		{
			name:    "invalid env",
			env:     map[string]string{"APP_ENV": "staging"},
			wantErr: "APP_ENV",
		},
		{
			name:    "invalid log level",
			env:     map[string]string{"LOG_LEVEL": "verbose"},
			wantErr: "LOG_LEVEL",
		},
		{
			name:    "addr without port",
			env:     map[string]string{"HTTP_ADDR": "8080"},
			wantErr: "HTTP_ADDR must be a host:port address",
		},
		{
			name:    "non-positive shutdown timeout",
			env:     map[string]string{"SHUTDOWN_TIMEOUT": "0s"},
			wantErr: "SHUTDOWN_TIMEOUT must be positive",
		},
		{
			name:    "unparsable shutdown timeout",
			env:     map[string]string{"SHUTDOWN_TIMEOUT": "soon"},
			wantErr: "not a valid duration",
		},
		{
			name:    "non-positive request timeout",
			env:     map[string]string{"REQUEST_TIMEOUT": "-5s"},
			wantErr: "REQUEST_TIMEOUT must be positive",
		},
		{
			name:    "empty http addr",
			env:     map[string]string{"HTTP_ADDR": "  "},
			wantErr: "HTTP_ADDR must not be empty",
		},
		{
			name: "multiple errors are joined",
			env: map[string]string{
				"APP_ENV":   "staging",
				"LOG_LEVEL": "verbose",
			},
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
			if got != tt.want {
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
