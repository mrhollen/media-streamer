package tlsutil

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestCertSHA256(t *testing.T) {
	dir := t.TempDir()
	certPath := filepath.Join(dir, "cert.pem")

	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("GenerateKey failed: %v", err)
	}

	template := x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject: pkix.Name{
			CommonName:   "test-cert",
			Organization: []string{"media-streamer"},
		},
		NotBefore: time.Now().Add(-time.Hour),
		NotAfter:  time.Now().Add(time.Hour),
		KeyUsage:  x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
	}

	der, err := x509.CreateCertificate(rand.Reader, &template, &template, &priv.PublicKey, priv)
	if err != nil {
		t.Fatalf("CreateCertificate failed: %v", err)
	}

	f, err := os.Create(certPath)
	if err != nil {
		t.Fatalf("Create cert file failed: %v", err)
	}

	if err := pem.Encode(f, &pem.Block{Type: "CERTIFICATE", Bytes: der}); err != nil {
		t.Fatalf("pem.Encode failed: %v", err)
	}
	_ = f.Close()

	fp, err := CertSHA256(certPath)
	if err != nil {
		t.Fatalf("CertSHA256 failed: %v", err)
	}
	if len(fp) != len("AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99") {
		t.Fatalf("unexpected fingerprint format: %s", fp)
	}
}
