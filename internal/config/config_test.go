package config

import (
	"errors"
	"strings"
	"testing"
)

func TestParseValidConfig(t *testing.T) {
	jsonData := `{
		"devices": [
			{
				"id": "camera",
				"name": "Front Camera",
				"type": "video",
				"ffmpeg_input": "/dev/video0",
				"ffmpeg_args": ["-f", "v4l2"],
				"output_codec": "libx264",
				"output_args": ["-preset", "veryfast"]
			},
			{
				"id": "mic",
				"name": "Desk Microphone",
				"type": "audio",
				"ffmpeg_input": "default"
			}
		]
	}`

	cfg, err := Parse([]byte(jsonData))
	if err != nil {
		t.Fatalf("Parse() error = %v", err)
	}

	if len(cfg.Devices) != 2 {
		t.Fatalf("expected 2 devices, got %d", len(cfg.Devices))
	}

	mic, ok := cfg.DeviceByID("mic")
	if !ok {
		t.Fatalf("expected to find device mic")
	}

	if mic.Type != DeviceTypeAudio {
		t.Fatalf("expected mic type audio, got %s", mic.Type)
	}

	if mic.FFmpegArgs == nil || len(mic.FFmpegArgs) != 0 {
		t.Fatalf("expected mic ffmpeg args to default to empty slice")
	}
	if mic.OutputArgs == nil || len(mic.OutputArgs) != 0 {
		t.Fatalf("expected mic output args to default to empty slice")
	}
}

func TestParseDuplicateDeviceID(t *testing.T) {
	jsonData := `{
		"devices": [
			{
				"id": "dup",
				"name": "One",
				"type": "video",
				"ffmpeg_input": "/dev/video0"
			},
			{
				"id": "dup",
				"name": "Two",
				"type": "audio",
				"ffmpeg_input": "default"
			}
		]
	}`

	_, err := Parse([]byte(jsonData))
	if err == nil {
		t.Fatalf("expected error for duplicate device id")
	}

	if !errors.Is(err, errDuplicateDeviceID) {
		t.Fatalf("expected errDuplicateDeviceID, got %v", err)
	}
}

func TestParseValidationErrors(t *testing.T) {
	tests := map[string]string{
		"missing id":    `{"devices":[{"id":"","name":"Name","type":"video","ffmpeg_input":"/dev/video0"}]}`,
		"missing name":  `{"devices":[{"id":"cam","name":"","type":"video","ffmpeg_input":"/dev/video0"}]}`,
		"invalid type":  `{"devices":[{"id":"cam","name":"Cam","type":"invalid","ffmpeg_input":"/dev/video0"}]}`,
		"missing input": `{"devices":[{"id":"cam","name":"Cam","type":"video","ffmpeg_input":""}]}`,
		"empty list":    `{"devices":[]}`,
	}

	for name, data := range tests {
		t.Run(name, func(t *testing.T) {
			_, err := Parse([]byte(data))
			if err == nil {
				t.Fatalf("expected error for %s", name)
			}

			if name == "empty list" && !strings.Contains(err.Error(), "at least one device") {
				t.Fatalf("expected empty list validation message, got %v", err)
			}
		})
	}
}
