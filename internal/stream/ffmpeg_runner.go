package stream

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/hollen/media-streamer/internal/config"
)

// FFMPEGRunner implements Runner using the ffmpeg binary.
type FFMPEGRunner struct {
	Binary string
	Logger *slog.Logger
}

// Start implements Runner.
func (r *FFMPEGRunner) Start(ctx context.Context, device config.Device) (io.ReadCloser, func() error, error) {
	logger := r.logger()
	logger.Info("Start: building FFmpeg command",
		slog.String("device_id", device.ID),
		slog.String("device_name", device.Name),
		slog.String("device_type", string(device.Type)),
		slog.String("ffmpeg_input", device.FFmpegInput),
		slog.String("binary", r.binary()))

	args := buildFFmpegArgs(device)
	logger.Info("Start: FFmpeg command arguments",
		slog.String("device_id", device.ID),
		slog.Any("args", args))

	cmd := exec.CommandContext(ctx, r.binary(), args...)

	logger.Info("Start: creating stdout pipe",
		slog.String("device_id", device.ID))
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		logger.Error("Start: ffmpeg stdout pipe failed",
			slog.String("device_id", device.ID),
			slog.String("error", err.Error()))
		return nil, nil, fmt.Errorf("ffmpeg stdout pipe: %w", err)
	}
	logger.Debug("Start: stdout pipe created",
		slog.String("device_id", device.ID))

	logger.Info("Start: creating stderr pipe",
		slog.String("device_id", device.ID))
	stderr, err := cmd.StderrPipe()
	if err != nil {
		logger.Error("Start: ffmpeg stderr pipe failed",
			slog.String("device_id", device.ID),
			slog.String("error", err.Error()))
		return nil, nil, fmt.Errorf("ffmpeg stderr pipe: %w", err)
	}
	logger.Debug("Start: stderr pipe created",
		slog.String("device_id", device.ID))

	logger.Info("Start: starting FFmpeg process",
		slog.String("device_id", device.ID))
	if err := cmd.Start(); err != nil {
		logger.Error("Start: ffmpeg process start failed",
			slog.String("device_id", device.ID),
			slog.String("error", err.Error()))
		return nil, nil, fmt.Errorf("ffmpeg start: %w", err)
	}

	if cmd.Process != nil {
		logger.Info("Start: FFmpeg process started",
			slog.String("device_id", device.ID),
			slog.Int("pid", cmd.Process.Pid))
	} else {
		logger.Warn("Start: FFmpeg process started but process handle is nil",
			slog.String("device_id", device.ID))
	}

	go func() {
		defer func() {
			logger.Debug("Start: stderr reader goroutine exiting",
				slog.String("device_id", device.ID))
			_ = stderr.Close()
		}()
		logger.Debug("Start: stderr reader goroutine started",
			slog.String("device_id", device.ID))
		scanner := bufio.NewScanner(stderr)
		scanner.Buffer(make([]byte, 0, 64*1024), 256*1024)
		lineCount := 0
		for scanner.Scan() {
			lineCount++
			line := scanner.Text()
			logger.Debug("ffmpeg stderr",
				slog.String("device_id", device.ID),
				slog.Int("line", lineCount),
				slog.String("msg", line))
		}
		if err := scanner.Err(); err != nil && !errors.Is(err, io.EOF) && !errors.Is(err, context.Canceled) {
			logger.Debug("Start: ffmpeg stderr read error",
				slog.String("device_id", device.ID),
				slog.String("error", err.Error()))
		}
		logger.Info("Start: stderr reader goroutine completed",
			slog.String("device_id", device.ID),
			slog.Int("lines_read", lineCount))
	}()

	cleanup := func() error {
		logger.Info("Start/cleanup: stopping FFmpeg process",
			slog.String("device_id", device.ID))
		waitCh := make(chan error, 1)
		go func() {
			waitCh <- cmd.Wait()
		}()
		select {
		case err := <-waitCh:
			logger.Info("Start/cleanup: FFmpeg process exited",
				slog.String("device_id", device.ID))
			if err != nil {
				logger.Debug("Start/cleanup: FFmpeg process exit returned error",
					slog.String("device_id", device.ID),
					slog.String("error", err.Error()))
			}
			if err != nil && !errors.Is(err, context.Canceled) {
				return err
			}
			return nil
		case <-ctx.Done():
			logger.Info("Start/cleanup: context cancelled, killing FFmpeg process",
				slog.String("device_id", device.ID),
				slog.String("ctx_error", ctx.Err().Error()))
			if cmd.Process != nil {
				logger.Debug("Start/cleanup: sending kill signal to FFmpeg process",
					slog.String("device_id", device.ID),
					slog.Int("pid", cmd.Process.Pid))
				if !errors.Is(cmd.Process.Kill(), os.ErrProcessDone) {
					logger.Debug("Start/cleanup: FFmpeg process killed due to context cancellation",
						slog.String("device_id", device.ID))
				} else {
					logger.Debug("Start/cleanup: FFmpeg process already done",
						slog.String("device_id", device.ID))
				}
			} else {
				logger.Debug("Start/cleanup: FFmpeg process handle is nil",
					slog.String("device_id", device.ID))
			}
			err := <-waitCh
			if err != nil && !errors.Is(err, context.Canceled) {
				logger.Debug("Start/cleanup: FFmpeg wait returned error after kill",
					slog.String("device_id", device.ID),
					slog.String("error", err.Error()))
				return err
			}
			return nil
		case <-time.After(2 * time.Second):
			logger.Warn("Start/cleanup: FFmpeg stop timed out, forcing kill",
				slog.String("device_id", device.ID))
			if cmd.Process != nil {
				logger.Debug("Start/cleanup: sending forced kill to FFmpeg process",
					slog.String("device_id", device.ID),
					slog.Int("pid", cmd.Process.Pid))
				if !errors.Is(cmd.Process.Kill(), os.ErrProcessDone) {
					logger.Warn("Start/cleanup: FFmpeg process forced kill after timeout",
						slog.String("device_id", device.ID))
				} else {
					logger.Debug("Start/cleanup: FFmpeg process already done on forced kill",
						slog.String("device_id", device.ID))
				}
			} else {
				logger.Debug("Start/cleanup: FFmpeg process handle is nil on timeout",
					slog.String("device_id", device.ID))
			}
			return <-waitCh
		}
	}

	logger.Info("Start: FFmpeg runner started successfully",
		slog.String("device_id", device.ID))
	return stdout, cleanup, nil
}

func (r *FFMPEGRunner) binary() string {
	if strings.TrimSpace(r.Binary) == "" {
		return "ffmpeg"
	}
	return r.Binary
}

func (r *FFMPEGRunner) logger() *slog.Logger {
	if r.Logger != nil {
		return r.Logger
	}
	return slog.Default()
}

func buildFFmpegArgs(device config.Device) []string {
	args := make([]string, 0, len(device.FFmpegArgs)+len(device.OutputArgs)+6)
	args = append(args, "-nostdin", "-loglevel", "error")
	if len(device.FFmpegArgs) > 0 {
		args = append(args, device.FFmpegArgs...)
	}

	// Only add -i <FFmpegInput> if FFmpegArgs doesn't already contain -i.
	// This guards against users who manually edit config.json and include
	// -i in FFmpegArgs, which would produce duplicate -i flags that break ffmpeg.
	if !hasInputFlag(device.FFmpegArgs) {
		args = append(args, "-i", device.FFmpegInput)
	}

	if codecFlag, ok := codecFlagForType(device.Type); ok && strings.TrimSpace(device.OutputCodec) != "" {
		args = append(args, codecFlag, device.OutputCodec)
	}

	if len(device.OutputArgs) > 0 {
		args = append(args, device.OutputArgs...)
	}

	args = append(args, "pipe:1")
	return args
}

// hasInputFlag reports whether args already contains the -i flag.
func hasInputFlag(args []string) bool {
	for _, arg := range args {
		if arg == "-i" {
			return true
		}
	}
	return false
}

func codecFlagForType(t config.DeviceType) (string, bool) {
	switch t {
	case config.DeviceTypeVideo:
		return "-c:v", true
	case config.DeviceTypeAudio:
		return "-c:a", true
	default:
		return "-c", false
	}
}
