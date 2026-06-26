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

func TestHasInputFlag(t *testing.T) {
	tests := []struct {
		name string
		args []string
		want bool
	}{
		{"nil slice", nil, false},
		{"empty slice", []string{}, false},
		{"no -i flag", []string{"-f", "v4l2", "-r", "30"}, false},
		{"-i at start", []string{"-i", "/dev/video0"}, true},
		{"-i in middle", []string{"-f", "v4l2", "-i", "/dev/video0"}, true},
		{"-i at end", []string{"-f", "v4l2", "-i"}, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := hasInputFlag(tt.args); got != tt.want {
				t.Errorf("hasInputFlag(%v) = %v, want %v", tt.args, got, tt.want)
			}
		})
	}
}

func TestBuildFFmpegArgsSkipsDuplicateInputFlag(t *testing.T) {
	// When FFmpegArgs already contains -i, buildFFmpegArgs must not append another -i.
	device := config.Device{
		ID:          "cam",
		Type:        config.DeviceTypeVideo,
		FFmpegInput: "/dev/video0",
		FFmpegArgs:  []string{"-f", "v4l2", "-i", "/dev/video0"},
		OutputCodec: "libx264",
	}

	args := buildFFmpegArgs(device)

	// Count occurrences of "-i" in the resulting args.
	count := 0
	for _, a := range args {
		if a == "-i" {
			count++
		}
	}
	if count != 1 {
		t.Fatalf("expected exactly one -i flag, got %d in args: %v", count, args)
	}
}

func TestBuildFFmpegArgsAddsInputFlagWhenMissing(t *testing.T) {
	// When FFmpegArgs does not contain -i, buildFFmpegArgs must append it.
	device := config.Device{
		ID:          "cam",
		Type:        config.DeviceTypeVideo,
		FFmpegInput: "/dev/video0",
		FFmpegArgs:  []string{"-f", "v4l2"},
		OutputCodec: "libx264",
	}

	args := buildFFmpegArgs(device)

	// Verify -i and the input value are present.
	found := false
	for i, a := range args {
		if a == "-i" && i+1 < len(args) && args[i+1] == "/dev/video0" {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("expected -i /dev/video0 in args: %v", args)
	}
}
