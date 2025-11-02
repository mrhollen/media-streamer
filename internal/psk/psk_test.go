package psk

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestGenerateWithDefaultEntropy(t *testing.T) {
	key, err := Generate(0)
	if err != nil {
		t.Fatalf("Generate() error = %v", err)
	}
	if len(key) == 0 {
		t.Fatalf("expected non-empty key")
	}
}

func TestGenerateDeterministicLength(t *testing.T) {
	key, err := Generate(32)
	if err != nil {
		t.Fatalf("Generate() error = %v", err)
	}
	// 32 bytes of entropy should produce 43 characters in Base64 (without padding).
	if want, got := 43, len(key); want != got {
		t.Fatalf("expected key length %d, got %d", want, got)
	}
}

func TestPrintOutputsKeyAndQr(t *testing.T) {
	const key = "test-psk"

	var buf bytes.Buffer
	if err := Print(key, &buf); err != nil {
		t.Fatalf("Print() error = %v", err)
	}

	out := buf.String()
	if !strings.Contains(out, key) {
		t.Fatalf("expected output to contain key, got %q", out)
	}
	if strings.Count(out, "\n") < 5 {
		t.Fatalf("expected multiline QR output, got %q", out)
	}
}

func TestPrintValidation(t *testing.T) {
	err := Print(" \t\n", &bytes.Buffer{})
	if err == nil {
		t.Fatalf("expected error for empty key")
	}

	err = Print("key", nil)
	if err == nil {
		t.Fatalf("expected error for nil writer")
	}
}

func TestEncodePNG(t *testing.T) {
	data, err := EncodePNG("test", 128)
	if err != nil {
		t.Fatalf("EncodePNG() error = %v", err)
	}
	if len(data) == 0 || !bytes.HasPrefix(data, []byte("\x89PNG")) {
		t.Fatalf("expected PNG header, got %v", data[:4])
	}
}

func TestLoadOrCreateCreatesFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "psk.txt")

	key, created, err := LoadOrCreate(path, 16)
	if err != nil {
		t.Fatalf("LoadOrCreate() error = %v", err)
	}
	if !created {
		t.Fatalf("expected key to be created")
	}
	if key == "" {
		t.Fatalf("expected non-empty key")
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read generated file: %v", err)
	}
	if strings.TrimSpace(string(data)) != key {
		t.Fatalf("file content mismatch, got %q", string(data))
	}
	if info, err := os.Stat(path); err == nil {
		if mode := info.Mode().Perm(); mode != 0o600 {
			t.Fatalf("expected file mode 0600, got %#o", mode)
		}
	} else {
		t.Fatalf("stat generated file: %v", err)
	}
}

func TestLoadOrCreateReadsExisting(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "psk.txt")
	const key = "existing-key"
	if err := os.WriteFile(path, []byte(key+"\n"), 0o600); err != nil {
		t.Fatalf("write existing key: %v", err)
	}

	loaded, created, err := LoadOrCreate(path, 16)
	if err != nil {
		t.Fatalf("LoadOrCreate() error = %v", err)
	}
	if created {
		t.Fatalf("expected existing key to be reused")
	}
	if loaded != key {
		t.Fatalf("expected %q, got %q", key, loaded)
	}
}

func TestPrintWithPayload(t *testing.T) {
	var buf bytes.Buffer
	if err := PrintWithPayload("secret", `{"psk":"secret","pin":"abcd"}`, &buf); err != nil {
		t.Fatalf("PrintWithPayload() error = %v", err)
	}
	out := buf.String()
	if !strings.Contains(out, "secret") {
		t.Fatalf("expected key in output")
	}
	if strings.Count(out, "\n") < 5 {
		t.Fatalf("expected multiline QR output")
	}
}

func TestEncodePayloadPNG(t *testing.T) {
	data, err := EncodePayloadPNG("secret", "payload", 128)
	if err != nil {
		t.Fatalf("EncodePayloadPNG() error = %v", err)
	}
	if len(data) == 0 || !bytes.HasPrefix(data, []byte("\x89PNG")) {
		t.Fatalf("expected PNG header")
	}
}
