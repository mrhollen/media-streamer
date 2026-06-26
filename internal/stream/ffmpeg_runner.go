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
	args := buildFFmpegArgs(device)

	cmd := exec.CommandContext(ctx, r.binary(), args...)

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, nil, fmt.Errorf("ffmpeg stdout pipe: %w", err)
	}

	stderr, err := cmd.StderrPipe()
	if err != nil {
		return nil, nil, fmt.Errorf("ffmpeg stderr pipe: %w", err)
	}

	if err := cmd.Start(); err != nil {
		return nil, nil, fmt.Errorf("ffmpeg start: %w", err)
	}

	logger := r.logger()
	go func() {
		defer func() {
			_ = stderr.Close()
		}()
		scanner := bufio.NewScanner(stderr)
		scanner.Buffer(make([]byte, 0, 64*1024), 256*1024)
		for scanner.Scan() {
			logger.Warn("ffmpeg", slog.String("msg", scanner.Text()))
		}
		if err := scanner.Err(); err != nil && !errors.Is(err, io.EOF) && !errors.Is(err, context.Canceled) {
			logger.Debug("ffmpeg stderr read error", slog.String("error", err.Error()))
		}
	}()

	cleanup := func() error {
		waitCh := make(chan error, 1)
		go func() {
			waitCh <- cmd.Wait()
		}()
		select {
		case err := <-waitCh:
			if err != nil && !errors.Is(err, context.Canceled) {
				return err
			}
			return nil
		case <-ctx.Done():
			if cmd.Process != nil && !errors.Is(cmd.Process.Kill(), os.ErrProcessDone) {
				logger.Debug("ffmpeg process killed due to context cancellation")
			}
			err := <-waitCh
			if err != nil && !errors.Is(err, context.Canceled) {
				return err
			}
			return nil
		case <-time.After(2 * time.Second):
			if cmd.Process != nil && !errors.Is(cmd.Process.Kill(), os.ErrProcessDone) {
				logger.Warn("ffmpeg process forced kill after timeout")
			}
			return <-waitCh
		}
	}

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
