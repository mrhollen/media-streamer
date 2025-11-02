package psk

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	qrcode "github.com/mdp/qrterminal/v3"
	qrgenerator "github.com/skip2/go-qrcode"
)

const (
	defaultEntropyBytes = 32
)

// Generate returns a Base64 URL-safe pre-shared key with the provided entropy bytes.
func Generate(entropyBytes int) (string, error) {
	if entropyBytes <= 0 {
		entropyBytes = defaultEntropyBytes
	}

	buf := make([]byte, entropyBytes)
	if _, err := rand.Read(buf); err != nil {
		return "", fmt.Errorf("generate psk: %w", err)
	}

	return base64.RawURLEncoding.EncodeToString(buf), nil
}

// Print writes the PSK and an accompanying ASCII QR code to the provided writer.
// The QR payload defaults to the key itself.
func Print(key string, out io.Writer) error {
	return PrintWithPayload(key, key, out)
}

// PrintWithPayload writes the PSK and QR code rendered from payload.
func PrintWithPayload(key, payload string, out io.Writer) error {
	if strings.TrimSpace(key) == "" {
		return fmt.Errorf("print psk: key cannot be empty")
	}

	if out == nil {
		return fmt.Errorf("print psk: writer cannot be nil")
	}

	if _, err := fmt.Fprintf(out, "Pre-Shared Key: %s\n\n", key); err != nil {
		return fmt.Errorf("print psk: %w", err)
	}

	cfg := qrcode.Config{
		Level:     qrcode.M,
		Writer:    out,
		BlackChar: qrcode.BLACK,
		WhiteChar: qrcode.WHITE,
		QuietZone: 1,
	}
	payload = strings.TrimSpace(payload)
	if payload == "" {
		payload = key
	}
	qrcode.GenerateWithConfig(payload, cfg)

	if _, err := fmt.Fprintln(out); err != nil {
		return fmt.Errorf("print psk: %w", err)
	}

	return nil
}

// EncodePNG returns a PNG-encoded QR code for the provided key.
func EncodePNG(key string, size int) ([]byte, error) {
	return EncodePayloadPNG(key, key, size)
}

// EncodePayloadPNG returns a PNG QR code using payload, defaulting to key when payload is empty.
func EncodePayloadPNG(key, payload string, size int) ([]byte, error) {
	if strings.TrimSpace(key) == "" {
		return nil, fmt.Errorf("encode qr: key cannot be empty")
	}
	payload = strings.TrimSpace(payload)
	if payload == "" {
		payload = key
	}
	if size <= 0 {
		size = 256
	}
	data, err := qrgenerator.Encode(payload, qrgenerator.Medium, size)
	if err != nil {
		return nil, fmt.Errorf("encode qr: %w", err)
	}
	return data, nil
}

// LoadOrCreate reads a PSK from path if it exists, otherwise generates a new one,
// writes it to disk, and returns it. The second return value indicates whether
// a new key was created.
func LoadOrCreate(path string, entropyBytes int) (string, bool, error) {
	if strings.TrimSpace(path) == "" {
		return "", false, errors.New("psk file path required")
	}

	data, err := os.ReadFile(path)
	if err == nil {
		key := strings.TrimSpace(string(data))
		if key == "" {
			return "", false, fmt.Errorf("psk file %s is empty", path)
		}
		return key, false, nil
	}

	if !errors.Is(err, os.ErrNotExist) {
		return "", false, fmt.Errorf("read psk file %s: %w", path, err)
	}

	key, genErr := Generate(entropyBytes)
	if genErr != nil {
		return "", false, genErr
	}

	dir := filepath.Dir(path)
	if dir != "" && dir != "." {
		if err := os.MkdirAll(dir, 0o700); err != nil {
			return "", false, fmt.Errorf("create psk directory: %w", err)
		}
	}

	content := append([]byte(key), '\n')
	if writeErr := os.WriteFile(path, content, 0o600); writeErr != nil {
		return "", false, fmt.Errorf("write psk file %s: %w", path, writeErr)
	}

	return key, true, nil
}
