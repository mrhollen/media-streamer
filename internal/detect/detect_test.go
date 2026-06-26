package detect

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"testing"
)

// ---------------------------------------------------------------------------
// Mock runner
// ---------------------------------------------------------------------------

type mockRunner struct {
	responses map[string]mockResponse
	callOrder []string
}

type mockResponse struct {
	stdout string
	stderr string
	err    error
}

func newMockRunner(responses map[string]mockResponse) *mockRunner {
	return &mockRunner{responses: responses}
}

func (m *mockRunner) Run(_ context.Context, cmd string, args ...string) (string, string, error) {
	key := cmd
	for _, a := range args {
		key += " " + a
	}
	m.callOrder = append(m.callOrder, key)
	if r, ok := m.responses[key]; ok {
		return r.stdout, r.stderr, r.err
	}
	return "", "", fmt.Errorf("mockRunner: no response for %q", key)
}

func exeError(name string) error {
	return &exec.Error{Name: name, Err: errors.New("executable file not found")}
}

// ---------------------------------------------------------------------------
// NewDetector
// ---------------------------------------------------------------------------

func TestNewDetector_NilRunner(t *testing.T) {
	d := NewDetector(nil)
	if d.Runner == nil {
		t.Fatal("expected DefaultRunner, got nil")
	}
	if _, ok := d.Runner.(*DefaultRunner); !ok {
		t.Fatal("expected *DefaultRunner")
	}
}

func TestNewDetector_CustomRunner(t *testing.T) {
	r := &mockRunner{}
	d := NewDetector(r)
	if d.Runner != r {
		t.Fatal("expected custom runner")
	}
}

// ---------------------------------------------------------------------------
// parseV4L2ListDevices
// ---------------------------------------------------------------------------

func TestParseV4L2ListDevices_SingleGroup(t *testing.T) {
	output := "USB Camera: USB Camera (usb-0000:00:14.0-6):\n    /dev/video0\n    /dev/video1\n    /dev/video14\n"
	groups := parseV4L2ListDevices(output)

	if len(groups) != 1 {
		t.Fatalf("expected 1 group, got %d", len(groups))
	}
	g := groups[0]
	if g.Name != "USB Camera: USB Camera (usb-0000:00:14.0-6)" {
		t.Errorf("unexpected name: %q", g.Name)
	}
	expectedPaths := []string{"/dev/video0", "/dev/video1", "/dev/video14"}
	if len(g.Paths) != len(expectedPaths) {
		t.Fatalf("expected %d paths, got %d", len(expectedPaths), len(g.Paths))
	}
	for i, p := range expectedPaths {
		if g.Paths[i] != p {
			t.Errorf("path[%d]: want %q, got %q", i, p, g.Paths[i])
		}
	}
}

func TestParseV4L2ListDevices_MultipleGroups(t *testing.T) {
	output := "Camera 1:\n    /dev/video0\n\nCamera 2:\n    /dev/video2\n    /dev/video3\n"
	groups := parseV4L2ListDevices(output)

	if len(groups) != 2 {
		t.Fatalf("expected 2 groups, got %d", len(groups))
	}
	if groups[0].Name != "Camera 1" {
		t.Errorf("group 0 name: want %q, got %q", "Camera 1", groups[0].Name)
	}
	if groups[1].Name != "Camera 2" {
		t.Errorf("group 1 name: want %q, got %q", "Camera 2", groups[1].Name)
	}
}

func TestParseV4L2ListDevices_Empty(t *testing.T) {
	groups := parseV4L2ListDevices("")
	if len(groups) != 0 {
		t.Fatalf("expected 0 groups, got %d", len(groups))
	}
}

func TestParseV4L2ListDevices_DuplicatePaths(t *testing.T) {
	// A path appears in two groups — the caller (buildVideoDevice) deduplicates.
	output := "Group A:\n    /dev/video0\n\nGroup B:\n    /dev/video0\n    /dev/video1\n"
	groups := parseV4L2ListDevices(output)
	if len(groups) != 2 {
		t.Fatalf("expected 2 groups, got %d", len(groups))
	}
	// Both groups should have /dev/video0.
	if groups[0].Paths[0] != "/dev/video0" || groups[1].Paths[0] != "/dev/video0" {
		t.Error("expected both groups to contain /dev/video0")
	}
}

// ---------------------------------------------------------------------------
// parseV4L2Formats
// ---------------------------------------------------------------------------

func TestParseV4L2Formats_Basic(t *testing.T) {
	output := `Interval: Frame rate
	640x480 (SIF)
	    30.00 image/s
	    15.00 image/s
	1280x720 (HD)
	    30.00 image/s
	    15.00 image/s
`
	formats := parseV4L2Formats(output)

	if len(formats) != 4 {
		t.Fatalf("expected 4 formats, got %d", len(formats))
	}

	// Check first format.
	if formats[0].Size != "640x480" {
		t.Errorf("format[0].Size: want %q, got %q", "640x480", formats[0].Size)
	}
	if formats[0].FrameRate != 30.0 {
		t.Errorf("format[0].FrameRate: want 30.0, got %f", formats[0].FrameRate)
	}

	// Check HD format.
	if formats[2].Size != "1280x720" {
		t.Errorf("format[2].Size: want %q, got %q", "1280x720", formats[2].Size)
	}
	if formats[2].FrameRate != 30.0 {
		t.Errorf("format[2].FrameRate: want 30.0, got %f", formats[2].FrameRate)
	}
}

func TestParseV4L2Formats_Empty(t *testing.T) {
	formats := parseV4L2Formats("")
	if len(formats) != 0 {
		t.Fatalf("expected 0 formats, got %d", len(formats))
	}
}

// ---------------------------------------------------------------------------
// pickBestFormat
// ---------------------------------------------------------------------------

func TestPickBestFormat_HighestResolution(t *testing.T) {
	formats := []v4l2Format{
		{Size: "640x480", Width: 640, Height: 480, FrameRate: 60.0},
		{Size: "1920x1080", Width: 1920, Height: 1080, FrameRate: 15.0},
		{Size: "1280x720", Width: 1280, Height: 720, FrameRate: 30.0},
	}

	best := pickBestFormat(formats)
	if best.Size != "1920x1080" {
		t.Errorf("want %q, got %q", "1920x1080", best.Size)
	}
}

func TestPickBestFormat_SameResolution_HighestFPS(t *testing.T) {
	formats := []v4l2Format{
		{Size: "1280x720", Width: 1280, Height: 720, FrameRate: 15.0},
		{Size: "1280x720", Width: 1280, Height: 720, FrameRate: 30.0},
		{Size: "1280x720", Width: 1280, Height: 720, FrameRate: 60.0},
	}

	best := pickBestFormat(formats)
	if best.FrameRate != 60.0 {
		t.Errorf("want 60.0, got %f", best.FrameRate)
	}
}

func TestPickBestFormat_Empty(t *testing.T) {
	best := pickBestFormat(nil)
	if best.Size != "640x480" {
		t.Errorf("want %q, got %q", "640x480", best.Size)
	}
}

// ---------------------------------------------------------------------------
// parsePulseAudioSources
// ---------------------------------------------------------------------------

func TestParsePulseAudioSources_Basic(t *testing.T) {
	output := `Source #0
	State: RUNNING
	Name: alsa_output.pci-0000_00_1f.3.analog-stereo.monitor
	Description: Monitor of Built-in Audio Analog Stereo
	sample spec: s16le 2ch 44100Hz

Source #1
	State: RUNNING
	Name: alsa_input.pci-0000_00_1f.3.analog-stereo
	Description: Built-in Audio Analog Stereo
	sample spec: s16le 2ch 48000Hz
`
	sources := parsePulseAudioSources(output)

	if len(sources) != 2 {
		t.Fatalf("expected 2 sources, got %d", len(sources))
	}

	if sources[0].Index != 0 {
		t.Errorf("source 0 index: want 0, got %d", sources[0].Index)
	}
	if sources[0].Name != "alsa_output.pci-0000_00_1f.3.analog-stereo.monitor" {
		t.Errorf("source 0 name: got %q", sources[0].Name)
	}
	if sources[0].Description != "Monitor of Built-in Audio Analog Stereo" {
		t.Errorf("source 0 description: got %q", sources[0].Description)
	}

	if sources[1].Name != "alsa_input.pci-0000_00_1f.3.analog-stereo" {
		t.Errorf("source 1 name: got %q", sources[1].Name)
	}
}

func TestParsePulseAudioSources_Empty(t *testing.T) {
	sources := parsePulseAudioSources("")
	if len(sources) != 0 {
		t.Fatalf("expected 0 sources, got %d", len(sources))
	}
}

func TestParsePulseAudioSources_NoDescription(t *testing.T) {
	output := `Source #0
	State: RUNNING
	Name: some-device
`
	sources := parsePulseAudioSources(output)
	if len(sources) != 1 {
		t.Fatalf("expected 1 source, got %d", len(sources))
	}
	// Description should fall back to Name.
	if sources[0].Description != "some-device" {
		t.Errorf("description fallback: want %q, got %q", "some-device", sources[0].Description)
	}
}

// ---------------------------------------------------------------------------
// parseALSAList
// ---------------------------------------------------------------------------

func TestParseALSAList_Basic(t *testing.T) {
	output := `**** List of PLAYBACK Hardware Devices ****
card 0: PCH [HDA Intel PCH], device 0: ALC897 Analog [ALC897 Analog]
card 1: NVidia [HDA NVidia], device 3: HDMI 0 [HDMI 0]
`
	devs := parseALSAList(output)

	if len(devs) != 2 {
		t.Fatalf("expected 2 devices, got %d", len(devs))
	}

	if devs[0].Card != 0 {
		t.Errorf("device 0 card: want 0, got %d", devs[0].Card)
	}
	if devs[0].Name != "HDA Intel PCH" {
		t.Errorf("device 0 name: got %q", devs[0].Name)
	}
	if devs[0].Desc != "ALC897 Analog" {
		t.Errorf("device 0 desc: got %q", devs[0].Desc)
	}

	if devs[1].Card != 1 {
		t.Errorf("device 1 card: want 1, got %d", devs[1].Card)
	}
	if devs[1].Desc != "HDMI 0" {
		t.Errorf("device 1 desc: got %q", devs[1].Desc)
	}
}

func TestParseALSAList_Empty(t *testing.T) {
	devs := parseALSAList("**** List of PLAYBACK Hardware Devices ****\n")
	if len(devs) != 0 {
		t.Fatalf("expected 0 devices, got %d", len(devs))
	}
}

// ---------------------------------------------------------------------------
// generateDeviceID
// ---------------------------------------------------------------------------

func TestGenerateDeviceID_Video(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"/dev/video0", "dev-video0"},
		{"/dev/video1", "dev-video1"},
		{"/dev/video14", "dev-video14"},
	}
	for _, tc := range tests {
		got := generateDeviceID(tc.input)
		if got != tc.expected {
			t.Errorf("generateDeviceID(%q): want %q, got %q", tc.input, tc.expected, got)
		}
	}
}

func TestGenerateDeviceID_PulseAudio(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"alsa_output.pci-0000_00_1f.3.analog-stereo.monitor", "alsa_output-pci-0000_00_1f-3-analog-stereo-monitor"},
		{"alsa_input.pci-0000_00_1f.3.analog-stereo", "alsa_input-pci-0000_00_1f-3-analog-stereo"},
	}
	for _, tc := range tests {
		got := generateDeviceID(tc.input)
		if got != tc.expected {
			t.Errorf("generateDeviceID(%q): want %q, got %q", tc.input, tc.expected, got)
		}
	}
}

func TestGenerateDeviceID_LeadingTrailingDashes(t *testing.T) {
	got := generateDeviceID("---test---")
	if got != "test" {
		t.Errorf("want %q, got %q", "test", got)
	}
}

// ---------------------------------------------------------------------------
// isExecutableNotFound
// ---------------------------------------------------------------------------

func TestIsExecutableNotFound(t *testing.T) {
	tests := []struct {
		name string
		err  error
		want bool
	}{
		{"nil", nil, false},
		{"exec error", exeError("v4l2-ctl"), true},
		{"generic error", errors.New("some other error"), false},
		{"message contains text", errors.New("executable file not found in PATH"), true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := isExecutableNotFound(tc.err)
			if got != tc.want {
				t.Errorf("isExecutableNotFound(%v): want %v, got %v", tc.err, tc.want, got)
			}
		})
	}
}

// ---------------------------------------------------------------------------
// Detector.Detect — full integration with mock
// ---------------------------------------------------------------------------

func TestDetect_VideoOnly(t *testing.T) {
	runner := newMockRunner(map[string]mockResponse{
		"v4l2-ctl --list-devices": {
			stdout: "USB Camera:\n    /dev/video0\n",
		},
		"v4l2-ctl --list-formats-ext -d /dev/video0": {
			stdout: `Interval: Frame rate
	640x480 (SIF)
	    30.00 image/s
	1280x720 (HD)
	    30.00 image/s
`,
		},
		"pactl list sources": {
			err: exeError("pactl"),
		},
		"aplay -l": {
			err: exeError("aplay"),
		},
	})

	d := NewDetector(runner)
	cfg, warnings, err := d.Detect(context.Background())

	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(cfg.Devices) != 1 {
		t.Fatalf("expected 1 device, got %d", len(cfg.Devices))
	}
	dev := cfg.Devices[0]
	if dev.Type != "video" {
		t.Errorf("device type: want video, got %s", dev.Type)
	}
	if dev.FFmpegInput != "/dev/video0" {
		t.Errorf("FFmpegInput: want %q, got %q", "/dev/video0", dev.FFmpegInput)
	}
	if dev.OutputCodec != "libx264" {
		t.Errorf("OutputCodec: want libx264, got %s", dev.OutputCodec)
	}

	// Should have warnings about missing audio tools.
	if len(warnings) == 0 {
		t.Error("expected warnings about missing audio tools")
	}
}

func TestDetect_AudioOnly(t *testing.T) {
	runner := newMockRunner(map[string]mockResponse{
		"v4l2-ctl --list-devices": {
			err: exeError("v4l2-ctl"),
		},
		"pactl list sources": {
			stdout: `Source #0
	State: RUNNING
	Name: alsa_input.pci-0000_00_1f.3.analog-stereo
	Description: Built-in Audio Analog Stereo
	sample spec: s16le 2ch 48000Hz
`,
		},
	})

	d := NewDetector(runner)
	cfg, warnings, err := d.Detect(context.Background())

	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(cfg.Devices) != 1 {
		t.Fatalf("expected 1 device, got %d", len(cfg.Devices))
	}
	dev := cfg.Devices[0]
	if dev.Type != "audio" {
		t.Errorf("device type: want audio, got %s", dev.Type)
	}
	if dev.OutputCodec != "libopus" {
		t.Errorf("OutputCodec: want libopus, got %s", dev.OutputCodec)
	}

	// Should have warning about missing v4l2-ctl.
	if len(warnings) == 0 {
		t.Error("expected warning about missing v4l2-ctl")
	}
}

func TestDetect_NoDevices(t *testing.T) {
	runner := newMockRunner(map[string]mockResponse{
		"v4l2-ctl --list-devices": {
			err: exeError("v4l2-ctl"),
		},
		"pactl list sources": {
			err: exeError("pactl"),
		},
		"aplay -l": {
			err: exeError("aplay"),
		},
	})

	d := NewDetector(runner)
	_, warnings, err := d.Detect(context.Background())

	if err == nil {
		t.Fatal("expected error, got nil")
	}
	if len(warnings) == 0 {
		t.Error("expected warnings")
	}
}

func TestDetect_SortedOutput(t *testing.T) {
	runner := newMockRunner(map[string]mockResponse{
		"v4l2-ctl --list-devices": {
			stdout: "Camera B:\n    /dev/video1\n\nCamera A:\n    /dev/video0\n",
		},
		"v4l2-ctl --list-formats-ext -d /dev/video1": {
			stdout: `Interval: Frame rate
	640x480
	    30.00 image/s
`,
		},
		"v4l2-ctl --list-formats-ext -d /dev/video0": {
			stdout: `Interval: Frame rate
	640x480
	    30.00 image/s
`,
		},
		"pactl list sources": {
			stdout: `Source #0
	State: RUNNING
	Name: alsa_input.pci-0000_00_1f.3.analog-stereo
	Description: Built-in Audio Analog Stereo
`,
		},
	})

	d := NewDetector(runner)
	cfg, _, err := d.Detect(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Devices should be sorted by ID: audio-0 < dev-video0 < dev-video1
	if len(cfg.Devices) != 3 {
		t.Fatalf("expected 3 devices, got %d", len(cfg.Devices))
	}
	if cfg.Devices[0].ID != "audio-0" {
		t.Errorf("first device ID: want %q, got %q", "audio-0", cfg.Devices[0].ID)
	}
	if cfg.Devices[1].ID != "dev-video0" {
		t.Errorf("second device ID: want %q, got %q", "dev-video0", cfg.Devices[1].ID)
	}
	if cfg.Devices[2].ID != "dev-video1" {
		t.Errorf("third device ID: want %q, got %q", "dev-video1", cfg.Devices[2].ID)
	}
}

func TestDetect_VideoFormatFallback(t *testing.T) {
	// When format query fails, device should still be added with fallback args.
	runner := newMockRunner(map[string]mockResponse{
		"v4l2-ctl --list-devices": {
			stdout: "USB Camera:\n    /dev/video0\n",
		},
		"v4l2-ctl --list-formats-ext -d /dev/video0": {
			stderr: "Device or resource busy",
			err:    fmt.Errorf("exit status 1"),
		},
		"pactl list sources": {
			err: exeError("pactl"),
		},
		"aplay -l": {
			err: exeError("aplay"),
		},
	})

	d := NewDetector(runner)
	cfg, _, err := d.Detect(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(cfg.Devices) != 1 {
		t.Fatalf("expected 1 device, got %d", len(cfg.Devices))
	}
	// Fallback device should have minimal FFmpegArgs.
	dev := cfg.Devices[0]
	if dev.FFmpegArgs[0] != "-f" || dev.FFmpegArgs[1] != "v4l2" {
		t.Errorf("fallback FFmpegArgs: got %v", dev.FFmpegArgs)
	}
}

func TestDetect_DuplicateVideoPaths(t *testing.T) {
	// Same device path listed under two groups should produce only one device.
	runner := newMockRunner(map[string]mockResponse{
		"v4l2-ctl --list-devices": {
			stdout: "Group A:\n    /dev/video0\n\nGroup B:\n    /dev/video0\n    /dev/video1\n",
		},
		"v4l2-ctl --list-formats-ext -d /dev/video0": {
			stdout: `Interval: Frame rate
	640x480
	    30.00 image/s
`,
		},
		"v4l2-ctl --list-formats-ext -d /dev/video1": {
			stdout: `Interval: Frame rate
	640x480
	    30.00 image/s
`,
		},
		"pactl list sources": {
			err: exeError("pactl"),
		},
		"aplay -l": {
			err: exeError("aplay"),
		},
	})

	d := NewDetector(runner)
	cfg, _, err := d.Detect(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(cfg.Devices) != 2 {
		t.Fatalf("expected 2 devices (deduplicated), got %d", len(cfg.Devices))
	}
}

// ---------------------------------------------------------------------------
// DefaultRunner.Run — smoke test with a real command
// ---------------------------------------------------------------------------

func TestDefaultRunner_Run_Echo(t *testing.T) {
	r := &DefaultRunner{}
	stdout, stderr, err := r.Run(context.Background(), "echo", "hello")

	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	got := strings.TrimSpace(stdout)
	if got != "hello" {
		t.Errorf("stdout: want %q, got %q", "hello", got)
	}
	if stderr != "" {
		t.Errorf("unexpected stderr: %q", stderr)
	}
}

func TestDefaultRunner_Run_NonExistent(t *testing.T) {
	r := &DefaultRunner{}
	_, _, err := r.Run(context.Background(), "nonexistent_command_12345")
	if err == nil {
		t.Fatal("expected error for non-existent command")
	}
}

func TestDefaultRunner_Run_ContextCancel(t *testing.T) {
	r := &DefaultRunner{}
	ctx, cancel := context.WithCancel(context.Background())
	cancel() // cancel immediately

	_, _, err := r.Run(ctx, "sleep", "10")
	if err == nil {
		t.Fatal("expected error from cancelled context")
	}
}

// ---------------------------------------------------------------------------
// detectALSADevices
// ---------------------------------------------------------------------------

func TestDetectALSADevices_Basic(t *testing.T) {
	runner := newMockRunner(map[string]mockResponse{
		"aplay -l": {
			stdout: `**** List of PLAYBACK Hardware Devices ****
card 0: PCH [HDA Intel PCH], device 0: ALC897 Analog [ALC897 Analog]
`,
		},
	})

	d := NewDetector(runner)
	devices, warnings := d.detectALSADevices(context.Background())

	if len(warnings) != 0 {
		t.Errorf("unexpected warnings: %v", warnings)
	}
	if len(devices) != 1 {
		t.Fatalf("expected 1 device, got %d", len(devices))
	}
	dev := devices[0]
	if dev.ID != "audio-alsa-0" {
		t.Errorf("ID: want %q, got %q", "audio-alsa-0", dev.ID)
	}
	if dev.OutputCodec != "libopus" {
		t.Errorf("OutputCodec: want libopus, got %s", dev.OutputCodec)
	}
}

func TestDetectALSADevices_NotFound(t *testing.T) {
	runner := newMockRunner(map[string]mockResponse{
		"aplay -l": {
			err: exeError("aplay"),
		},
	})

	d := NewDetector(runner)
	devices, warnings := d.detectALSADevices(context.Background())

	if len(devices) != 0 {
		t.Errorf("expected 0 devices, got %d", len(devices))
	}
	if len(warnings) != 1 {
		t.Fatalf("expected 1 warning, got %d", len(warnings))
	}
}
