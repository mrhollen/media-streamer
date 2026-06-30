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

	w := &Worker{
		runner:       r,
		logger:       logger,
		writeTimeout: 5 * time.Second,
		bufferSize:   32 * 1024,
	}

	slog.Info("NewWorker: worker constructed",
		slog.Duration("write_timeout", w.writeTimeout),
		slog.Int("buffer_size", w.bufferSize),
		slog.Bool("runner_configured", r != nil))

	return w
}

// Handle streams the device output to the websocket connection.
func (w *Worker) Handle(ctx context.Context, device config.Device, conn *websocket.Conn) error {
	slog.Info("Handle: starting stream worker",
		slog.String("device_id", device.ID),
		slog.String("device_name", device.Name),
		slog.String("device_type", string(device.Type)),
		slog.String("ffmpeg_input", device.FFmpegInput))

	if w.runner == nil {
		slog.Error("Handle: runner is not configured")
		return errors.New("stream worker: runner is not configured")
	}

	slog.Info("Handle: starting FFmpeg runner",
		slog.String("device_id", device.ID))
	reader, cleanup, err := w.runner.Start(ctx, device)
	if err != nil {
		slog.Error("Handle: runner.Start failed",
			slog.String("device_id", device.ID),
			slog.String("error", err.Error()))
		return err
	}
	slog.Info("Handle: runner started successfully",
		slog.String("device_id", device.ID))

	defer func() {
		slog.Info("Handle: running cleanup",
			slog.String("device_id", device.ID))
		if reader != nil {
			slog.Debug("Handle: closing reader",
				slog.String("device_id", device.ID))
			_ = reader.Close()
		}
		if cleanup != nil {
			slog.Debug("Handle: calling runner cleanup",
				slog.String("device_id", device.ID))
			if cerr := cleanup(); cerr != nil && !errors.Is(cerr, context.Canceled) {
				w.logger.Warn("Handle: cleanup failed",
					slog.String("device_id", device.ID),
					slog.String("error", cerr.Error()))
			} else {
				slog.Debug("Handle: cleanup completed",
					slog.String("device_id", device.ID))
			}
		}
	}()

	slog.Info("Handle: entering read loop",
		slog.String("device_id", device.ID),
		slog.Int("buffer_size", w.bufferSize))
	buf := make([]byte, w.bufferSize)
	iterations := 0
	for {
		iterations++
		n, readErr := reader.Read(buf)

		if n > 0 {
			slog.Debug("Handle: read data from FFmpeg",
				slog.String("device_id", device.ID),
				slog.Int("bytes_read", n),
				slog.Int("iteration", iterations))

			writeCtx, cancel := context.WithTimeout(ctx, w.writeTimeout)
			slog.Debug("Handle: writing data to WebSocket",
				slog.String("device_id", device.ID),
				slog.Int("bytes_to_write", n),
				slog.Int("iteration", iterations))
			err := conn.Write(writeCtx, websocket.MessageBinary, buf[:n])
			cancel()
			if err != nil {
				slog.Error("Handle: WebSocket write failed",
					slog.String("device_id", device.ID),
					slog.Int("bytes_to_write", n),
					slog.Int("iteration", iterations),
					slog.String("error", err.Error()))
				return err
			}
			slog.Debug("Handle: wrote data to WebSocket successfully",
				slog.String("device_id", device.ID),
				slog.Int("bytes_written", n),
				slog.Int("iteration", iterations))
		} else {
			slog.Debug("Handle: read returned zero bytes",
				slog.String("device_id", device.ID),
				slog.Int("iteration", iterations))
		}

		if readErr != nil {
			slog.Info("Handle: read loop exited due to error",
				slog.String("device_id", device.ID),
				slog.String("error", readErr.Error()),
				slog.Int("total_iterations", iterations))
			if errors.Is(readErr, io.EOF) {
				slog.Info("Handle: FFmpeg output EOF - stream ended normally",
					slog.String("device_id", device.ID))
				return nil
			}
			slog.Error("Handle: read error - terminating stream",
				slog.String("device_id", device.ID),
				slog.String("error", readErr.Error()))
			return readErr
		}
	}
}
