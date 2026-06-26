// Package detect auto-detects media devices on Linux and generates a config.Config.
//
// It executes OS command-line tools (v4l2-ctl, pactl, aplay) to discover available
// video and audio capture devices. It never reads device files directly.
package detect

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"regexp"
	"sort"
	"strings"

	"github.com/hollen/media-streamer/internal/config"
)

// CommandRunner abstracts command execution for testability.
type CommandRunner interface {
	Run(ctx context.Context, cmd string, args ...string) (stdout string, stderr string, err error)
}

// DefaultRunner executes real OS commands using exec.Command.
type DefaultRunner struct{}

// Run executes the given command with arguments, capturing stdout and stderr separately.
func (r *DefaultRunner) Run(ctx context.Context, cmd string, args ...string) (string, string, error) {
	command := exec.CommandContext(ctx, cmd, args...)
	var stdoutBuf, stderrBuf strings.Builder
	command.Stdout = &stdoutBuf
	command.Stderr = &stderrBuf
	err := command.Run()
	return stdoutBuf.String(), stderrBuf.String(), err
}

// Detector discovers media devices on the system.
type Detector struct {
	Runner CommandRunner
}

// NewDetector creates a Detector. If runner is nil, a DefaultRunner is used.
func NewDetector(runner CommandRunner) *Detector {
	if runner == nil {
		runner = &DefaultRunner{}
	}
	return &Detector{Runner: runner}
}

// Detect scans for available video and audio devices and returns a generated config.
// The warnings slice contains non-fatal issues (e.g., a detection tool was missing).
func (d *Detector) Detect(ctx context.Context) (config.Config, []string, error) {
	var devices []config.Device
	var warnings []string

	videoDevices, w := d.detectVideoDevices(ctx)
	devices = append(devices, videoDevices...)
	warnings = append(warnings, w...)

	audioDevices, w := d.detectAudioDevices(ctx)
	devices = append(devices, audioDevices...)
	warnings = append(warnings, w...)

	if len(devices) == 0 {
		return config.Config{}, warnings, fmt.Errorf("no devices detected")
	}

	// Sort by ID for deterministic output.
	sort.Slice(devices, func(i, j int) bool {
		return devices[i].ID < devices[j].ID
	})

	return config.Config{Devices: devices}, warnings, nil
}

// ---------------------------------------------------------------------------
// Video detection
// ---------------------------------------------------------------------------

// v4l2DeviceGroup represents a named group of device paths from v4l2-ctl output.
type v4l2DeviceGroup struct {
	Name string
	Paths []string
}

func (d *Detector) detectVideoDevices(ctx context.Context) ([]config.Device, []string) {
	stdout, stderr, err := d.Runner.Run(ctx, "v4l2-ctl", "--list-devices")
	if err != nil {
		if isExecutableNotFound(err) {
			return nil, []string{"v4l2-ctl not found, skipping video detection"}
		}
		return nil, []string{fmt.Sprintf("v4l2-ctl --list-devices failed: %v (stderr: %s)", err, strings.TrimSpace(stderr))}
	}

	groups := parseV4L2ListDevices(stdout)
	if len(groups) == 0 {
		return nil, []string{"v4l2-ctl --list-devices returned no devices"}
	}

	var devices []config.Device
	seenPaths := make(map[string]struct{})

	for _, group := range groups {
		for _, path := range group.Paths {
			if _, dup := seenPaths[path]; dup {
				continue
			}
			seenPaths[path] = struct{}{}

			dev, err := d.buildVideoDevice(ctx, path, group.Name)
			if err != nil {
				// Non-fatal: warn but continue with other devices.
				devices = append(devices, d.buildVideoDeviceFallback(path, group.Name))
				continue
			}
			devices = append(devices, dev)
		}
	}

	return devices, nil
}

func (d *Detector) buildVideoDevice(ctx context.Context, path, deviceName string) (config.Device, error) {
	formats, err := d.queryV4L2Formats(ctx, path)
	if err != nil {
		return config.Device{}, fmt.Errorf("build device for %s: %w", path, err)
	}

	best := pickBestFormat(formats)

	return config.Device{
		ID:          generateDeviceID(path),
		Name:        deviceName,
		Type:        config.DeviceTypeVideo,
		FFmpegInput: path,
		FFmpegArgs:  []string{"-f", "v4l2", "-framerate", fmt.Sprintf("%.2f", best.FrameRate), "-video_size", best.Size},
		OutputCodec: "libx264",
		OutputArgs:  []string{"-preset", "ultrafast", "-tune", "zerolatency", "-f", "h264"},
	}, nil
}

func (d *Detector) buildVideoDeviceFallback(path, deviceName string) config.Device {
	return config.Device{
		ID:          generateDeviceID(path),
		Name:        deviceName,
		Type:        config.DeviceTypeVideo,
		FFmpegInput: path,
		FFmpegArgs:  []string{"-f", "v4l2"},
		OutputCodec: "libx264",
		OutputArgs:  []string{"-preset", "ultrafast", "-tune", "zerolatency", "-f", "h264"},
	}
}

// v4l2Format represents a single resolution/framerate combination.
type v4l2Format struct {
	Size      string // e.g. "1280x720"
	Width     int
	Height    int
	FrameRate float64
}

func (d *Detector) queryV4L2Formats(ctx context.Context, path string) ([]v4l2Format, error) {
	stdout, stderr, err := d.Runner.Run(ctx, "v4l2-ctl", "--list-formats-ext", "-d", path)
	if err != nil {
		return nil, fmt.Errorf("v4l2-ctl --list-formats-ext -d %s: %w (stderr: %s)", path, err, strings.TrimSpace(stderr))
	}
	return parseV4L2Formats(stdout), nil
}

// ---------------------------------------------------------------------------
// Audio detection
// ---------------------------------------------------------------------------

func (d *Detector) detectAudioDevices(ctx context.Context) ([]config.Device, []string) {
	// Try PulseAudio / PipeWire first.
	devices, warnings := d.detectPulseAudioDevices(ctx)
	if len(devices) > 0 || len(warnings) > 0 {
		return devices, warnings
	}

	// Fall back to ALSA.
	return d.detectALSADevices(ctx)
}

// pulseSource holds parsed PulseAudio source information.
type pulseSource struct {
	Index       int
	Name        string
	Description string
}

func (d *Detector) detectPulseAudioDevices(ctx context.Context) ([]config.Device, []string) {
	stdout, stderr, err := d.Runner.Run(ctx, "pactl", "list", "sources")
	if err != nil {
		if isExecutableNotFound(err) {
			return nil, []string{"pactl not found, falling back to ALSA detection"}
		}
		return nil, []string{fmt.Sprintf("pactl list sources failed: %v (stderr: %s)", err, strings.TrimSpace(stderr))}
	}

	sources := parsePulseAudioSources(stdout)
	if len(sources) == 0 {
		return nil, []string{"pactl returned no audio sources, falling back to ALSA detection"}
	}

	var devices []config.Device
	for _, src := range sources {
		devices = append(devices, config.Device{
			ID:          fmt.Sprintf("audio-%d", src.Index),
			Name:        src.Description,
			Type:        config.DeviceTypeAudio,
			FFmpegInput: src.Name,
			FFmpegArgs:  []string{"-f", "pulse"},
			OutputCodec: "libopus",
			OutputArgs:  []string{"-b:a", "128k", "-f", "opus"},
		})
	}

	return devices, nil
}

// alsaDevice holds parsed ALSA device information.
type alsaDevice struct {
	Card   int
	Name   string
	Desc   string
}

func (d *Detector) detectALSADevices(ctx context.Context) ([]config.Device, []string) {
	stdout, stderr, err := d.Runner.Run(ctx, "aplay", "-l")
	if err != nil {
		if isExecutableNotFound(err) {
			return nil, []string{"aplay not found, skipping audio detection"}
		}
		return nil, []string{fmt.Sprintf("aplay -l failed: %v (stderr: %s)", err, strings.TrimSpace(stderr))}
	}

	devs := parseALSAList(stdout)
	if len(devs) == 0 {
		return nil, []string{"aplay -l returned no devices"}
	}

	var devices []config.Device
	for _, alsa := range devs {
		devices = append(devices, config.Device{
			ID:          fmt.Sprintf("audio-alsa-%d", alsa.Card),
			Name:        alsa.Desc,
			Type:        config.DeviceTypeAudio,
			FFmpegInput: fmt.Sprintf("hw:%d,%d", alsa.Card, alsa.Card),
			FFmpegArgs:  []string{"-f", "alsa"},
			OutputCodec: "libopus",
			OutputArgs:  []string{"-b:a", "128k", "-f", "opus"},
		})
	}

	return devices, nil
}

// ---------------------------------------------------------------------------
// Parsing helpers
// ---------------------------------------------------------------------------

// parseV4L2ListDevices parses the grouped output of `v4l2-ctl --list-devices`.
//
// Output format:
//
//	USB Camera: USB Camera (usb-0000:00:14.0-6):
//	    /dev/video0
//	    /dev/video1
//	    /dev/video14
func parseV4L2ListDevices(output string) []v4l2DeviceGroup {
	var groups []v4l2DeviceGroup

	// Header line: non-indented, ends with ":"
	headerRe := regexp.MustCompile(`^([^\t\n][^\n]*):$`)
	// Device path line: indented with spaces, starts with /dev/
	pathRe := regexp.MustCompile(`^\s+(/dev/\S+)$`)

	currentGroup := &v4l2DeviceGroup{}
	inGroup := false

	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimRight(line, "\r")

		if m := headerRe.FindStringSubmatch(line); m != nil {
			if inGroup && len(currentGroup.Paths) > 0 {
				groups = append(groups, *currentGroup)
			}
			currentGroup = &v4l2DeviceGroup{Name: strings.TrimSpace(m[1])}
			inGroup = true
			continue
		}

		if m := pathRe.FindStringSubmatch(line); m != nil {
			currentGroup.Paths = append(currentGroup.Paths, m[1])
			continue
		}

		// Empty or unexpected line: finalize the current group if we were in one.
		if inGroup && len(currentGroup.Paths) > 0 {
			groups = append(groups, *currentGroup)
			currentGroup = &v4l2DeviceGroup{}
			inGroup = false
		}
	}

	if inGroup && len(currentGroup.Paths) > 0 {
		groups = append(groups, *currentGroup)
	}

	return groups
}

// parseV4L2Formats parses the extended format listing from `v4l2-ctl --list-formats-ext`.
func parseV4L2Formats(output string) []v4l2Format {
	var formats []v4l2Format

	sizeRe := regexp.MustCompile(`^\s+(\d+)x(\d+)\b`)
	fpsRe := regexp.MustCompile(`([\d.]+)\s+image/s`)

	var currentWidth, currentHeight int

	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimRight(line, "\r")

		if m := sizeRe.FindStringSubmatch(line); m != nil {
			currentWidth, _ = parseInt(m[1])
			currentHeight, _ = parseInt(m[2])
			continue
		}

		if m := fpsRe.FindStringSubmatch(line); m != nil && currentWidth > 0 && currentHeight > 0 {
			fps, _ := parseFloat(m[1])
			formats = append(formats, v4l2Format{
				Size:      fmt.Sprintf("%dx%d", currentWidth, currentHeight),
				Width:     currentWidth,
				Height:    currentHeight,
				FrameRate: fps,
			})
		}
	}

	return formats
}

// pickBestFormat returns the format with the highest pixel count, breaking ties
// by highest framerate.
func pickBestFormat(formats []v4l2Format) v4l2Format {
	if len(formats) == 0 {
		return v4l2Format{Size: "640x480", Width: 640, Height: 480, FrameRate: 30.0}
	}

	best := formats[0]
	for _, f := range formats[1:] {
		bestPixels := best.Width * best.Height
		candPixels := f.Width * f.Height
		if candPixels > bestPixels || (candPixels == bestPixels && f.FrameRate > best.FrameRate) {
			best = f
		}
	}
	return best
}

// parsePulseAudioSources parses `pactl list sources` output.
func parsePulseAudioSources(output string) []pulseSource {
	var sources []pulseSource

	// Split into source blocks by "Source #N" lines.
	sourceHeaderRe := regexp.MustCompile(`^Source #(\d+)$`)
	nameRe := regexp.MustCompile(`^\s+Name:\s+(.+)$`)
	descRe := regexp.MustCompile(`^\s+Description:\s+(.+)$`)

	var currentIdx int
	var currentName, currentDesc string
	inSource := false

	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimRight(line, "\r")

		if m := sourceHeaderRe.FindStringSubmatch(line); m != nil {
			// Finalize previous source block.
			if inSource && currentName != "" {
				desc := currentDesc
				if desc == "" {
					desc = currentName
				}
				sources = append(sources, pulseSource{
					Index:       currentIdx,
					Name:        currentName,
					Description: desc,
				})
			}
			currentIdx, _ = parseInt(m[1])
			currentName = ""
			currentDesc = ""
			inSource = true
			continue
		}

		if !inSource {
			continue
		}

		if m := nameRe.FindStringSubmatch(line); m != nil {
			currentName = strings.TrimSpace(m[1])
		}
		if m := descRe.FindStringSubmatch(line); m != nil {
			currentDesc = strings.TrimSpace(m[1])
		}
	}

	// Finalize the last source block.
	if inSource && currentName != "" {
		desc := currentDesc
		if desc == "" {
			desc = currentName
		}
		sources = append(sources, pulseSource{
			Index:       currentIdx,
			Name:        currentName,
			Description: desc,
		})
	}

	return sources
}

// parseALSAList parses `aplay -l` output.
func parseALSAList(output string) []alsaDevice {
	var devices []alsaDevice

	re := regexp.MustCompile(`card\s+(\d+):\s+[^[]+\[([^\]]+)\],\s+device\s+(\d+):\s+[^[]+\[([^\]]+)\]`)

	for _, m := range re.FindAllStringSubmatch(output, -1) {
		if len(m) < 5 {
			continue
		}
		card, _ := parseInt(m[1])
		devices = append(devices, alsaDevice{
			Card: card,
			Name: m[2],
			Desc: m[4],
		})
	}

	return devices
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

// generateDeviceID creates a sanitized, URL-safe identifier from a device path.
//
// Examples:
//
//	"/dev/video0" -> "dev-video0"
//	"alsa_output.pci-0000_00_1f.3.monitor" -> "alsa-output-pci-0000_00_1f-3-monitor"
func generateDeviceID(path string) string {
	// Replace slashes with dashes so "/dev/video0" becomes "dev-video0".
	// This avoids collisions like /dev/video0 vs /dev/video00.
	s := strings.ReplaceAll(path, "/", "-")

	// Replace dots with dashes.
	s = strings.ReplaceAll(s, ".", "-")

	// Collapse multiple dashes.
	dashRe := regexp.MustCompile(`-+`)
	s = dashRe.ReplaceAllString(s, "-")

	// Trim leading/trailing dashes.
	s = strings.Trim(s, "-")

	return s
}

// isExecutableNotFound checks whether the error indicates the command binary
// could not be found on the system.
func isExecutableNotFound(err error) bool {
	if err == nil {
		return false
	}
	// exec.Error wraps "executable file not found"
	if ee := (*exec.Error)(nil); errors.As(err, &ee) {
		return true
	}
	// Fallback: check the error message text.
	return strings.Contains(err.Error(), "executable file not found")
}

func parseInt(s string) (int, error) {
	var n int
	_, err := fmt.Sscanf(s, "%d", &n)
	return n, err
}

func parseFloat(s string) (float64, error) {
	var f float64
	_, err := fmt.Sscanf(s, "%f", &f)
	return f, err
}
