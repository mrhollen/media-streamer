package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/hollen/media-streamer/internal/config"
	"nhooyr.io/websocket"
)

// StreamHandler streams the requested device over the supplied websocket connection.
type StreamHandler interface {
	Handle(ctx context.Context, device config.Device, conn *websocket.Conn) error
}

// Options configure the server behaviour.
type Options struct {
	Logger       *slog.Logger
	ReadTimeout  time.Duration
	WriteTimeout time.Duration
	TLSCertFile  string
	TLSKeyFile   string
}

// Server exposes the HTTP API surface for clients.
type Server struct {
	cfg          config.Config
	psk          string
	streams      StreamHandler
	httpServer   *http.Server
	logger       *slog.Logger
	readTimeout  time.Duration
	writeTimeout time.Duration
	tlsCertFile  string
	tlsKeyFile   string
}

// New constructs a Server instance.
func New(cfg config.Config, psk string, handler StreamHandler, opts *Options) (*Server, error) {
	if strings.TrimSpace(psk) == "" {
		return nil, errors.New("psk must not be empty")
	}

	var logger *slog.Logger
	readTimeout := 5 * time.Second
	writeTimeout := 10 * time.Second
	tlsCert := ""
	tlsKey := ""

	if opts != nil {
		if opts.Logger != nil {
			logger = opts.Logger
		}
		if opts.ReadTimeout > 0 {
			readTimeout = opts.ReadTimeout
		}
		if opts.WriteTimeout > 0 {
			writeTimeout = opts.WriteTimeout
		}
		tlsCert = strings.TrimSpace(opts.TLSCertFile)
		tlsKey = strings.TrimSpace(opts.TLSKeyFile)
	}

	if logger == nil {
		logger = slog.Default()
	}

	if (tlsCert == "") != (tlsKey == "") {
		return nil, errors.New("both TLS certificate and key must be provided")
	}

	s := &Server{
		cfg:          cfg,
		psk:          psk,
		streams:      handler,
		logger:       logger,
		readTimeout:  readTimeout,
		writeTimeout: writeTimeout,
		tlsCertFile:  tlsCert,
		tlsKeyFile:   tlsKey,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /devices", s.devicesHandler)
	mux.HandleFunc("GET /stream/", s.streamHandler)

	s.httpServer = &http.Server{
		Handler:      mux,
		ReadTimeout:  s.readTimeout,
		WriteTimeout: s.writeTimeout,
	}

	return s, nil
}

// ListenAndServe starts serving HTTP until the context is cancelled.
func (s *Server) ListenAndServe(ctx context.Context, addr string) error {
	s.httpServer.Addr = addr

	errCh := make(chan error, 1)
	go func() {
		if s.tlsCertFile != "" {
			errCh <- s.httpServer.ListenAndServeTLS(s.tlsCertFile, s.tlsKeyFile)
		} else {
			errCh <- s.httpServer.ListenAndServe()
		}
	}()

	select {
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := s.httpServer.Shutdown(shutdownCtx); err != nil && !errors.Is(err, context.Canceled) {
			s.logger.Error("http shutdown failed", slog.String("error", err.Error()))
		}
		return ctx.Err()
	case err := <-errCh:
		if err == http.ErrServerClosed {
			return nil
		}
		return err
	}
}

func (s *Server) devicesHandler(w http.ResponseWriter, r *http.Request) {
	if !s.authorizeHTTP(r) {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	devices := s.cfg.SortedCopy()
	type deviceView struct {
		ID   string            `json:"id"`
		Name string            `json:"name"`
		Type config.DeviceType `json:"type"`
	}

	views := make([]deviceView, len(devices))
	for i, d := range devices {
		views[i] = deviceView{
			ID:   d.ID,
			Name: d.Name,
			Type: d.Type,
		}
	}

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(views); err != nil {
		s.logger.Error("encode devices response failed", slog.String("error", err.Error()))
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
	}
}

func (s *Server) streamHandler(w http.ResponseWriter, r *http.Request) {
	if s.streams == nil {
		http.Error(w, "Streaming not configured", http.StatusServiceUnavailable)
		return
	}

	deviceID := strings.TrimPrefix(r.URL.Path, "/stream/")
	if strings.TrimSpace(deviceID) == "" {
		http.Error(w, "Device Not Found", http.StatusNotFound)
		return
	}

	device, ok := s.cfg.DeviceByID(deviceID)
	if !ok {
		http.Error(w, "Device Not Found", http.StatusNotFound)
		return
	}

	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		CompressionMode: websocket.CompressionDisabled,
	})
	if err != nil {
		s.logger.Error("websocket accept failed", slog.String("error", err.Error()))
		return
	}

	closeStatus := websocket.StatusInternalError
	closeReason := "internal error"
	defer func() {
		if err := conn.Close(closeStatus, closeReason); err != nil {
			s.logger.Debug("websocket close", slog.String("error", err.Error()))
		}
	}()

	if err := s.authorizeWebsocket(r.Context(), conn); err != nil {
		closeStatus = websocket.StatusPolicyViolation
		closeReason = err.Error()
		return
	}

	if err := s.streams.Handle(r.Context(), device, conn); err != nil {
		s.logger.Error("stream failed", slog.String("device_id", device.ID), slog.String("error", err.Error()))
		return
	}

	closeStatus = websocket.StatusNormalClosure
	closeReason = ""
}

func (s *Server) authorizeHTTP(r *http.Request) bool {
	header := r.Header.Get("Authorization")
	if header == "" {
		return false
	}
	const bearerPrefix = "Bearer "
	if !strings.HasPrefix(header, bearerPrefix) {
		return false
	}
	token := strings.TrimSpace(strings.TrimPrefix(header, bearerPrefix))
	return token == s.psk
}

func (s *Server) authorizeWebsocket(ctx context.Context, conn *websocket.Conn) error {
	authCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	msgType, payload, err := conn.Read(authCtx)
	if err != nil {
		return fmt.Errorf("authentication failed: %w", err)
	}

	if msgType != websocket.MessageText {
		return errors.New("authentication requires text frame")
	}

	if strings.TrimSpace(string(payload)) != s.psk {
		return errors.New("invalid pre-shared key")
	}

	return nil
}
