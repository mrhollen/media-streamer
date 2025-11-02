package config

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"sort"
	"strings"
)

// DeviceType defines the kind of media that a device provides.
type DeviceType string

const (
	DeviceTypeVideo DeviceType = "video"
	DeviceTypeAudio DeviceType = "audio"
)

var (
	errDuplicateDeviceID = errors.New("duplicate device id")
)

// Device describes a single ffmpeg-backed streaming source.
type Device struct {
	ID          string     `json:"id"`
	Name        string     `json:"name"`
	Type        DeviceType `json:"type"`
	FFmpegInput string     `json:"ffmpeg_input"`
	FFmpegArgs  []string   `json:"ffmpeg_args"`
	OutputCodec string     `json:"output_codec"`
	OutputArgs  []string   `json:"output_args"`
}

// Config is the top-level configuration.
type Config struct {
	Devices []Device `json:"devices"`
}

// Load reads the config file from disk and validates it.
func Load(path string) (Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Config{}, fmt.Errorf("read config %q: %w", path, err)
	}

	return Parse(data)
}

// Parse decodes JSON configuration data and validates it.
func Parse(data []byte) (Config, error) {
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return Config{}, fmt.Errorf("decode config: %w", err)
	}

	if err := cfg.validate(); err != nil {
		return Config{}, err
	}

	return cfg, nil
}

// DeviceByID returns the device with the provided id or false if not present.
func (c Config) DeviceByID(id string) (Device, bool) {
	for _, device := range c.Devices {
		if device.ID == id {
			return device, true
		}
	}
	return Device{}, false
}

// SortedCopy returns a copy of the device slice ordered by id.
func (c Config) SortedCopy() []Device {
	devices := make([]Device, len(c.Devices))
	copy(devices, c.Devices)
	sort.Slice(devices, func(i, j int) bool {
		return devices[i].ID < devices[j].ID
	})
	return devices
}

func (c *Config) validate() error {
	if len(c.Devices) == 0 {
		return errors.New("config must define at least one device")
	}

	seenIDs := make(map[string]struct{}, len(c.Devices))
	for i := range c.Devices {
		device := &c.Devices[i]
		if err := device.validate(); err != nil {
			return fmt.Errorf("device %d: %w", i, err)
		}

		if _, ok := seenIDs[device.ID]; ok {
			return fmt.Errorf("%w: %s", errDuplicateDeviceID, device.ID)
		}
		seenIDs[device.ID] = struct{}{}

		if device.FFmpegArgs == nil {
			device.FFmpegArgs = []string{}
		}
		if device.OutputArgs == nil {
			device.OutputArgs = []string{}
		}
	}

	return nil
}

func (d *Device) validate() error {
	if strings.TrimSpace(d.ID) == "" {
		return errors.New("device id is required")
	}
	if strings.TrimSpace(d.Name) == "" {
		return fmt.Errorf("device %q name is required", d.ID)
	}

	switch d.Type {
	case DeviceTypeAudio, DeviceTypeVideo:
		// ok
	default:
		return fmt.Errorf("device %q type %q is invalid", d.ID, d.Type)
	}

	if strings.TrimSpace(d.FFmpegInput) == "" {
		return fmt.Errorf("device %q ffmpeg_input is required", d.ID)
	}

	return nil
}
