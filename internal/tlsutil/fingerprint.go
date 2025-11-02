package tlsutil

import (
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/pem"
	"fmt"
	"os"
	"strings"
)

// CertSHA256 reads the certificate at path and returns the SHA-256 fingerprint
// of the first PEM block.
func CertSHA256(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("read cert %s: %w", path, err)
	}

	block, _ := pem.Decode(data)
	if block == nil {
		return "", fmt.Errorf("no PEM block found in %s", path)
	}

	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return "", fmt.Errorf("parse certificate %s: %w", path, err)
	}

	sum := sha256.Sum256(cert.Raw)
	return formatFingerprint(sum[:]), nil
}

func formatFingerprint(raw []byte) string {
	hexed := strings.ToUpper(hex.EncodeToString(raw))
	var builder strings.Builder
	for i := 0; i < len(hexed); i += 2 {
		if i > 0 {
			builder.WriteByte(':')
		}
		builder.WriteString(hexed[i : i+2])
	}
	return builder.String()
}
