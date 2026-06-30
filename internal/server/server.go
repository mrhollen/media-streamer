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
		slog.Error("NewServer: psk must not be empty")
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

	slog.Info("NewServer: constructing server",
		slog.Duration("read_timeout", readTimeout),
		slog.Duration("write_timeout", writeTimeout),
		slog.Bool("tls_enabled", tlsCert != "" && tlsKey != ""),
		slog.Int("device_count", len(cfg.Devices)))

	if (tlsCert == "") != (tlsKey == "") {
		slog.Error("NewServer: both TLS certificate and key must be provided",
			slog.String("tls_cert", tlsCert),
			slog.String("tls_key", tlsKey))
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

	slog.Info("NewServer: server constructed successfully")
	return s, nil
}

// ListenAndServe starts serving HTTP until the context is cancelled.
func (s *Server) ListenAndServe(ctx context.Context, addr string) error {
	s.httpServer.Addr = addr
	slog.Info("ListenAndServe: setting server address", slog.String("addr", addr))

	errCh := make(chan error, 1)
	go func() {
		if s.tlsCertFile != "" {
			slog.Info("ListenAndServe: starting HTTPS server",
				slog.String("addr", addr),
				slog.String("tls_cert", s.tlsCertFile),
				slog.String("tls_key", s.tlsKeyFile))
			errCh <- s.httpServer.ListenAndServeTLS(s.tlsCertFile, s.tlsKeyFile)
		} else {
			slog.Info("ListenAndServe: starting HTTP server", slog.String("addr", addr))
			errCh <- s.httpServer.ListenAndServe()
		}
	}()

	slog.Info("ListenAndServe: waiting for server events")
	select {
	case <-ctx.Done():
		slog.Info("ListenAndServe: context cancelled, initiating shutdown")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		slog.Info("ListenAndServe: calling http.Server.Shutdown", slog.Duration("timeout", 5*time.Second))
		if err := s.httpServer.Shutdown(shutdownCtx); err != nil && !errors.Is(err, context.Canceled) {
			s.logger.Error("ListenAndServe: http shutdown failed", slog.String("error", err.Error()))
		}
		slog.Info("ListenAndServe: shutdown complete")
		return ctx.Err()
	case err := <-errCh:
		slog.Info("ListenAndServe: received error from http server", slog.String("error", err.Error()))
		if err == http.ErrServerClosed {
			slog.Info("ListenAndServe: server closed cleanly")
			return nil
		}
		slog.Error("ListenAndServe: server returned error", slog.String("error", err.Error()))
		return err
	}
}

func (s *Server) devicesHandler(w http.ResponseWriter, r *http.Request) {
	slog.Info("devicesHandler: incoming request",
		slog.String("method", r.Method),
		slog.String("path", r.URL.Path),
		slog.String("remote_addr", r.RemoteAddr))

	if !s.authorizeHTTP(r) {
		slog.Warn("devicesHandler: authorization failed",
			slog.String("remote_addr", r.RemoteAddr))
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	devices := s.cfg.SortedCopy()
	slog.Info("devicesHandler: returning device list",
		slog.Int("device_count", len(devices)))
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
		s.logger.Error("devicesHandler: encode devices response failed",
			slog.String("error", err.Error()),
			slog.Int("device_count", len(devices)))
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}
	slog.Debug("devicesHandler: response encoded and sent successfully",
		slog.Int("device_count", len(devices)))
}

func (s *Server) streamHandler(w http.ResponseWriter, r *http.Request) {
	slog.Info("streamHandler: incoming request",
		slog.String("method", r.Method),
		slog.String("path", r.URL.Path),
		slog.String("remote_addr", r.RemoteAddr))

	if s.streams == nil {
		slog.Error("streamHandler: streaming not configured")
		http.Error(w, "Streaming not configured", http.StatusServiceUnavailable)
		return
	}

	deviceID := strings.TrimPrefix(r.URL.Path, "/stream/")
	slog.Info("streamHandler: extracted device ID from URL",
		slog.String("device_id", deviceID))

	if strings.TrimSpace(deviceID) == "" {
		slog.Warn("streamHandler: empty device ID in URL")
		http.Error(w, "Device Not Found", http.StatusNotFound)
		return
	}

	slog.Info("streamHandler: looking up device", slog.String("device_id", deviceID))
	device, ok := s.cfg.DeviceByID(deviceID)
	if !ok {
		slog.Warn("streamHandler: device not found", slog.String("device_id", deviceID))
		http.Error(w, "Device Not Found", http.StatusNotFound)
		return
	}
	slog.Info("streamHandler: device found",
		slog.String("device_id", device.ID),
		slog.String("device_name", device.Name),
		slog.String("device_type", string(device.Type)))

	slog.Info("streamHandler: attempting WebSocket upgrade",
		slog.String("device_id", device.ID),
		slog.String("remote_addr", r.RemoteAddr))
	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		CompressionMode: websocket.CompressionDisabled,
	})
	if err != nil {
		s.logger.Error("streamHandler: websocket accept failed",
			slog.String("device_id", device.ID),
			slog.String("error", err.Error()))
		return
	}
	slog.Info("streamHandler: WebSocket upgrade successful",
		slog.String("device_id", device.ID))

	closeStatus := websocket.StatusInternalError
	closeReason := "internal error"
	defer func() {
		slog.Debug("streamHandler: closing WebSocket connection",
			slog.Int("close_status", int(closeStatus)),
			slog.String("close_reason", closeReason))
		if err := conn.Close(closeStatus, closeReason); err != nil {
			s.logger.Debug("streamHandler: websocket close returned error",
				slog.String("error", err.Error()))
		}
	}()

	slog.Info("streamHandler: starting PSK authentication",
		slog.String("device_id", device.ID))
	if err := s.authorizeWebsocket(r.Context(), conn); err != nil {
		slog.Warn("streamHandler: PSK authentication failed",
			slog.String("device_id", device.ID),
			slog.String("error", err.Error()))
		closeStatus = websocket.StatusPolicyViolation
		closeReason = err.Error()
		return
	}
	slog.Info("streamHandler: PSK authentication successful",
		slog.String("device_id", device.ID))

	slog.Info("streamHandler: dispatching to stream handler",
		slog.String("device_id", device.ID))
	if err := s.streams.Handle(r.Context(), device, conn); err != nil {
		s.logger.Error("streamHandler: stream failed",
			slog.String("device_id", device.ID),
			slog.String("error", err.Error()))
		return
	}
	slog.Info("streamHandler: stream completed successfully",
		slog.String("device_id", device.ID))

	closeStatus = websocket.StatusNormalClosure
	closeReason = ""
}

func (s *Server) authorizeHTTP(r *http.Request) bool {
	header := r.Header.Get("Authorization")
	if header == "" {
		slog.Debug("authorizeHTTP: missing Authorization header",
			slog.String("remote_addr", r.RemoteAddr))
		return false
	}
	slog.Debug("authorizeHTTP: received Authorization header",
		slog.String("remote_addr", r.RemoteAddr))
	const bearerPrefix = "Bearer "
	if !strings.HasPrefix(header, bearerPrefix) {
		slog.Debug("authorizeHTTP: Authorization header does not start with 'Bearer '",
			slog.String("remote_addr", r.RemoteAddr))
		return false
	}
	token := strings.TrimSpace(strings.TrimPrefix(header, bearerPrefix))
	match := token == s.psk
	if match {
		slog.Debug("authorizeHTTP: authentication successful",
			slog.String("remote_addr", r.RemoteAddr))
	} else {
		slog.Warn("authorizeHTTP: authentication failed - token mismatch",
			slog.String("remote_addr", r.RemoteAddr))
	}
	return match
}

func (s *Server) authorizeWebsocket(ctx context.Context, conn *websocket.Conn) error {
	slog.Debug("authorizeWebsocket: waiting for auth message",
		slog.Duration("timeout", 5*time.Second))
	authCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	msgType, payload, err := conn.Read(authCtx)
	if err != nil {
		slog.Error("authorizeWebsocket: failed to read auth message",
			slog.String("error", err.Error()))
		return fmt.Errorf("authentication failed: %w", err)
	}
	slog.Debug("authorizeWebsocket: received auth message",
		slog.Int("msg_type", int(msgType)),
		slog.Int("payload_length", len(payload)))

	if msgType != websocket.MessageText {
		slog.Warn("authorizeWebsocket: expected text frame, got different message type",
			slog.Int("msg_type", int(msgType)))
		return errors.New("authentication requires text frame")
	}

	match := strings.TrimSpace(string(payload)) == s.psk
	if !match {
		slog.Warn("authorizeWebsocket: PSK mismatch - authentication failed")
		return errors.New("invalid pre-shared key")
	}

	slog.Debug("authorizeWebsocket: PSK matches - authentication successful")
	return nil
}
