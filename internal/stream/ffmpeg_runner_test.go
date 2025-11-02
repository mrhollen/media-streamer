package stream

import (
	"strings"
	"testing"

	"github.com/hollen/media-streamer/internal/config"
)

func TestBuildFFmpegArgsVideo(t *testing.T) {
	device := config.Device{
		ID:          "cam",
		Type:        config.DeviceTypeVideo,
		FFmpegInput: "/dev/video0",
		FFmpegArgs:  []string{"-f", "v4l2"},
		OutputCodec: "libx264",
		OutputArgs:  []string{"-preset", "fast", "-f", "h264"},
	}

	args := buildFFmpegArgs(device)
	cmd := strings.Join(args, " ")

	if !strings.Contains(cmd, "-c:v libx264") {
		t.Fatalf("expected video codec flag, args: %s", cmd)
	}
	if !strings.HasSuffix(cmd, "pipe:1") {
		t.Fatalf("expected pipe:1 output, args: %s", cmd)
	}
}

func TestBuildFFmpegArgsAudio(t *testing.T) {
	device := config.Device{
		ID:          "mic",
		Type:        config.DeviceTypeAudio,
		FFmpegInput: "default",
		OutputCodec: "libopus",
	}

	args := buildFFmpegArgs(device)
	cmd := strings.Join(args, " ")

	if strings.Contains(cmd, "-c:v") {
		t.Fatalf("unexpected video codec flag in %s", cmd)
	}
	if !strings.Contains(cmd, "-c:a libopus") {
		t.Fatalf("expected audio codec flag, got %s", cmd)
	}
}
