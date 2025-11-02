package stream

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"time"

	"github.com/hollen/media-streamer/internal/config"
	"nhooyr.io/websocket"
)

// Runner abstracts the ffmpeg subprocess lifecycle for testability.
type Runner interface {
	// Start launches the subprocess and returns a reader for its stdout along
	// with a cleanup function that must be called to release resources.
	Start(ctx context.Context, device config.Device) (io.ReadCloser, func() error, error)
}

// Worker coordinates moving data from a Runner to a websocket connection.
type Worker struct {
	runner       Runner
	logger       *slog.Logger
	writeTimeout time.Duration
	bufferSize   int
}

// NewWorker constructs a Worker.
func NewWorker(r Runner, logger *slog.Logger) *Worker {
	if logger == nil {
		logger = slog.Default()
	}

	return &Worker{
		runner:       r,
		logger:       logger,
		writeTimeout: 5 * time.Second,
		bufferSize:   32 * 1024,
	}
}

// Handle streams the device output to the websocket connection.
func (w *Worker) Handle(ctx context.Context, device config.Device, conn *websocket.Conn) error {
	if w.runner == nil {
		return errors.New("stream worker: runner is not configured")
	}

	reader, cleanup, err := w.runner.Start(ctx, device)
	if err != nil {
		return err
	}
	defer func() {
		if reader != nil {
			_ = reader.Close()
		}
		if cleanup != nil {
			if cerr := cleanup(); cerr != nil && !errors.Is(cerr, context.Canceled) {
				w.logger.Warn("cleanup failed", slog.String("error", cerr.Error()))
			}
		}
	}()

	buf := make([]byte, w.bufferSize)
	for {
		n, readErr := reader.Read(buf)
		if n > 0 {
			writeCtx, cancel := context.WithTimeout(ctx, w.writeTimeout)
			err := conn.Write(writeCtx, websocket.MessageBinary, buf[:n])
			cancel()
			if err != nil {
				return err
			}
		}

		if readErr != nil {
			if errors.Is(readErr, io.EOF) {
				return nil
			}
			return readErr
		}
	}
}
