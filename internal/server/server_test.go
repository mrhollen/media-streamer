package server

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/hollen/media-streamer/internal/config"
	"github.com/hollen/media-streamer/internal/stream"
	"nhooyr.io/websocket"
)

func newTestServer(t *testing.T, handler StreamHandler) *Server {
	t.Helper()
	cfg := config.Config{
		Devices: []config.Device{
			{ID: "b", Name: "Device B", Type: config.DeviceTypeAudio, FFmpegInput: "default"},
			{ID: "a", Name: "Device A", Type: config.DeviceTypeVideo, FFmpegInput: "/dev/video0"},
		},
	}

	if handler == nil {
		handler = streamStub{}
	}

	srv, err := New(cfg, "secret", handler, nil)
	if err != nil {
		t.Fatalf("New() error = %v", err)
	}
	return srv
}

func TestDevicesUnauthorized(t *testing.T) {
	srv := newTestServer(t, nil)

	req := httptest.NewRequest(http.MethodGet, "/devices", nil)
	rec := httptest.NewRecorder()

	srv.httpServer.Handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected status 401, got %d", rec.Code)
	}
}

func TestDevicesAuthorized(t *testing.T) {
	srv := newTestServer(t, nil)

	req := httptest.NewRequest(http.MethodGet, "/devices", nil)
	req.Header.Set("Authorization", "Bearer secret")
	rec := httptest.NewRecorder()

	srv.httpServer.Handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rec.Code)
	}

	if ct := rec.Header().Get("Content-Type"); !strings.Contains(ct, "application/json") {
		t.Fatalf("expected application/json content type, got %q", ct)
	}

	var devices []map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &devices); err != nil {
		t.Fatalf("failed decoding response: %v", err)
	}

	if len(devices) != 2 {
		t.Fatalf("expected 2 devices, got %d", len(devices))
	}

	if devices[0]["id"] != "a" || devices[1]["id"] != "b" {
		t.Fatalf("expected devices sorted by id, got %+v", devices)
	}
}

type streamStub struct{}

func (streamStub) Handle(ctx context.Context, device config.Device, conn *websocket.Conn) error {
	return nil
}

type streamingStub struct {
	frames [][]byte
}

func (s streamingStub) Handle(ctx context.Context, device config.Device, conn *websocket.Conn) error {
	for _, frame := range s.frames {
		if err := conn.Write(ctx, websocket.MessageBinary, frame); err != nil {
			return err
		}
	}
	return nil
}

func TestStreamInvalidDevice(t *testing.T) {
	srv := newTestServer(t, streamingStub{})

	req := httptest.NewRequest(http.MethodGet, "/stream/unknown", nil)
	rec := httptest.NewRecorder()

	srv.httpServer.Handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for unknown device, got %d", rec.Code)
	}
}

func TestStreamRejectsInvalidKey(t *testing.T) {
	srv := newTestServer(t, streamingStub{})
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	conn := dialWebsocket(t, ctx, srv.httpServer.Handler, "/stream/a")
	defer conn.Close(websocket.StatusNormalClosure, "")

	if err := conn.Write(ctx, websocket.MessageText, []byte("wrong")); err != nil {
		t.Fatalf("Write() error = %v", err)
	}

	_, _, readErr := conn.Read(ctx)
	var closeErr websocket.CloseError
	if !errors.As(readErr, &closeErr) {
		t.Fatalf("expected websocket close error, got %v", readErr)
	}
	if closeErr.Code != websocket.StatusPolicyViolation {
		t.Fatalf("expected policy violation, got %d", closeErr.Code)
	}
}

func TestStreamSuccess(t *testing.T) {
	runner := &runnerStub{
		chunks: [][]byte{
			{0x00, 0x01, 0x02},
			{0x03, 0x04},
		},
	}
	handler := stream.NewWorker(runner, nil)
	srv := newTestServer(t, handler)
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	conn := dialWebsocket(t, ctx, srv.httpServer.Handler, "/stream/a")
	defer conn.Close(websocket.StatusNormalClosure, "")

	if err := conn.Write(ctx, websocket.MessageText, []byte("secret")); err != nil {
		t.Fatalf("auth write error: %v", err)
	}

	var received bytes.Buffer
	var closeErr websocket.CloseError
	for {
		typ, data, err := conn.Read(ctx)
		if err != nil {
			if errors.As(err, &closeErr) {
				break
			}
			t.Fatalf("Read() error = %v", err)
		}
		if typ != websocket.MessageBinary {
			t.Fatalf("expected binary frame, got %v", typ)
		}
		if _, err := received.Write(data); err != nil {
			t.Fatalf("buffer write error: %v", err)
		}
	}

	if closeErr.Code != websocket.StatusNormalClosure {
		t.Fatalf("expected normal closure, got %d", closeErr.Code)
	}

	if !bytes.Equal(received.Bytes(), []byte{0x00, 0x01, 0x02, 0x03, 0x04}) {
		t.Fatalf("unexpected payload %v", received.Bytes())
	}

	if !runner.cleanupCalled {
		t.Fatalf("expected runner cleanup to be called")
	}
}

func TestNewRequiresTLSPair(t *testing.T) {
	cfg := config.Config{
		Devices: []config.Device{
			{ID: "cam", Name: "Camera", Type: config.DeviceTypeVideo, FFmpegInput: "/dev/video0"},
		},
	}

	if _, err := New(cfg, "secret", streamStub{}, &Options{TLSCertFile: "cert.pem"}); err == nil {
		t.Fatalf("expected error when TLS key missing")
	}

	if _, err := New(cfg, "secret", streamStub{}, &Options{TLSKeyFile: "key.pem"}); err == nil {
		t.Fatalf("expected error when TLS cert missing")
	}
}

type runnerStub struct {
	chunks        [][]byte
	cleanupCalled bool
}

func (r *runnerStub) Start(ctx context.Context, device config.Device) (io.ReadCloser, func() error, error) {
	pr, pw := io.Pipe()
	go func() {
		for _, chunk := range r.chunks {
			if _, err := pw.Write(chunk); err != nil {
				break
			}
		}
		_ = pw.Close()
	}()

	cleanup := func() error {
		r.cleanupCalled = true
		return nil
	}

	return pr, cleanup, nil
}

func dialWebsocket(t *testing.T, ctx context.Context, handler http.Handler, path string) *websocket.Conn {
	t.Helper()
	transport := &wsTestTransport{handler: handler}
	client := &http.Client{Transport: transport}
	conn, _, err := websocket.Dial(ctx, "ws://example.com"+path, &websocket.DialOptions{
		HTTPClient: client,
	})
	if err != nil {
		t.Fatalf("websocket dial failed: %v", err)
	}
	return conn
}

type wsTestTransport struct {
	handler http.Handler
}

func (t *wsTestTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	clientConn, serverConn := net.Pipe()
	hj := newTestHijacker(serverConn)

	go t.handler.ServeHTTP(hj, r)

	select {
	case <-hj.headerWritten:
	case <-time.After(time.Second):
		_ = serverConn.Close()
		_ = clientConn.Close()
		return nil, errors.New("websocket handshake timeout")
	}

	resp := hj.Result()
	if resp.StatusCode == http.StatusSwitchingProtocols {
		resp.Body = clientConn
	} else {
		_ = serverConn.Close()
		_ = clientConn.Close()
	}
	return resp, nil
}

type testHijacker struct {
	*httptest.ResponseRecorder
	conn          net.Conn
	headerWritten chan struct{}
	headerOnce    sync.Once
	hijackOnce    sync.Once
}

func newTestHijacker(conn net.Conn) *testHijacker {
	return &testHijacker{
		ResponseRecorder: httptest.NewRecorder(),
		conn:             conn,
		headerWritten:    make(chan struct{}, 1),
	}
}

func (hj *testHijacker) WriteHeader(statusCode int) {
	hj.ResponseRecorder.WriteHeader(statusCode)
	hj.headerOnce.Do(func() {
		hj.headerWritten <- struct{}{}
		close(hj.headerWritten)
	})
}

func (hj *testHijacker) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	hj.hijackOnce.Do(func() {
		// Ensure headerWritten is closed if Hijack occurs before WriteHeader.
		hj.headerOnce.Do(func() {
			close(hj.headerWritten)
		})
	})
	return hj.conn, bufio.NewReadWriter(bufio.NewReader(hj.conn), bufio.NewWriter(hj.conn)), nil
}

var _ http.Hijacker = (*testHijacker)(nil)
