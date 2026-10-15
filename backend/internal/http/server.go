package httpapi

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"time"
)

// NewServer builds the HTTP server. Only ReadHeaderTimeout is set globally:
// a global ReadTimeout or WriteTimeout would cap the whole body read (bad for
// audio uploads) and the whole response (bad for long AI calls), so slow work
// is bounded per request instead via withRequestTimeout and the caller's ctx.
func NewServer(handler http.Handler, logger *slog.Logger) *http.Server {
	return &http.Server{
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       120 * time.Second,
		ErrorLog:          slog.NewLogLogger(logger.Handler(), slog.LevelError),
	}
}

// Run serves requests on ln until ctx is cancelled, then drains in-flight
// requests within shutdownTimeout before returning. The listener is created by
// the caller so that a failed bind is reported before any "listening" log line.
func Run(ctx context.Context, srv *http.Server, ln net.Listener, logger *slog.Logger, shutdownTimeout time.Duration) error {
	serveErr := make(chan error, 1)
	go func() {
		if err := srv.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serveErr <- err
			return
		}
		serveErr <- nil
	}()

	logger.Info("http server listening", "addr", ln.Addr().String())

	select {
	case err := <-serveErr:
		return err
	case <-ctx.Done():
	}

	logger.Info("shutdown requested, draining connections", "timeout", shutdownTimeout)

	shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		return fmt.Errorf("graceful shutdown: %w", err)
	}

	if err := <-serveErr; err != nil {
		return err
	}
	logger.Info("http server stopped")
	return nil
}
