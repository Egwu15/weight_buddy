package httpapi

import (
	"context"
	"net"
	"net/http"
	"testing"
	"time"
)

func TestRunServesThenShutsDown(t *testing.T) {
	logger := testLogger()

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listening: %v", err)
	}
	srv := NewServer(NewRouter(Deps{Logger: logger}), logger)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	done := make(chan error, 1)
	go func() { done <- Run(ctx, srv, ln, logger, 5*time.Second) }()

	waitForHealthy(t, "http://"+ln.Addr().String()+"/healthz")

	cancel()

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("Run returned error: %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("Run did not return after context cancellation")
	}
}

func TestRunReturnsServeError(t *testing.T) {
	logger := testLogger()

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listening: %v", err)
	}
	// Close the listener out from under the server to force Serve to fail.
	if err := ln.Close(); err != nil {
		t.Fatalf("closing listener: %v", err)
	}

	srv := NewServer(NewRouter(Deps{Logger: logger}), logger)

	if err := Run(context.Background(), srv, ln, logger, time.Second); err == nil {
		t.Fatal("expected an error from a closed listener, got nil")
	}
}

func waitForHealthy(t *testing.T, url string) {
	t.Helper()
	client := &http.Client{Timeout: time.Second}
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		resp, err := client.Get(url)
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				return
			}
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("server at %s never became healthy", url)
}
