package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/hollen/media-streamer/internal/config"
	"github.com/hollen/media-streamer/internal/detect"
	"github.com/hollen/media-streamer/internal/psk"
	"github.com/hollen/media-streamer/internal/server"
	"github.com/hollen/media-streamer/internal/stream"
	"github.com/hollen/media-streamer/internal/tlsutil"
)

func main() {
	var (
		configPath string
		host       string
		port       int
		addr       string
		ffmpegBin  string
		pskPNG     string
		pskFile    string
		tlsCert    string
		tlsKey     string
		detectMode bool
	)

	flag.StringVar(&configPath, "config", "config.json", "Path to config.json")
	flag.StringVar(&host, "host", "0.0.0.0", "Host interface to bind")
	flag.IntVar(&port, "port", 8080, "HTTP listen port")
	flag.StringVar(&addr, "addr", "", "Optional listen address (overrides host and port)")
	flag.StringVar(&ffmpegBin, "ffmpeg", "", "Path to ffmpeg binary (defaults to FFmpeg in PATH)")
	flag.StringVar(&pskPNG, "psk-png", "", "Optional path to write the PSK QR code as a PNG file")
	flag.StringVar(&pskFile, "psk-file", "", "Path to a file containing the PSK (created if missing)")
	flag.StringVar(&tlsCert, "tls-cert", "", "Path to TLS certificate file")
	flag.StringVar(&tlsKey, "tls-key", "", "Path to TLS private key file")
	flag.BoolVar(&detectMode, "detect", false, "Detect available devices and generate a config (does not start the server)")
	flag.Parse()

	if detectMode {
		runDetect(configPath)
		return
	}

	logger := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelInfo}))

	cfg, err := config.Load(configPath)
	if err != nil {
		fatal(err)
	}
	if (strings.TrimSpace(tlsCert) == "") != (strings.TrimSpace(tlsKey) == "") {
		fatal(errors.New("both --tls-cert and --tls-key must be provided"))
	}

	var (
		key     string
		created bool
	)
	if strings.TrimSpace(pskFile) != "" {
		key, created, err = psk.LoadOrCreate(pskFile, 0)
		if err != nil {
			fatal(err)
		}
		if created {
			fmt.Printf("Generated new PSK and stored in %s\n", pskFile)
		} else {
			fmt.Printf("Loaded PSK from %s\n", pskFile)
		}
	} else {
		key, err = psk.Generate(0)
		if err != nil {
			fatal(err)
		}
	}

	qrPayload := key
	if strings.TrimSpace(tlsCert) != "" {
		fp, err := tlsutil.CertSHA256(tlsCert)
		if err != nil {
			fatal(err)
		}
		fmt.Printf("TLS certificate SHA-256 fingerprint: %s\n", fp)
		payload := map[string]string{
			"psk":          key,
			"tls_sha256":   strings.ReplaceAll(fp, ":", ""),
			"tls_friendly": fp,
		}
		if payloadBytes, err := json.Marshal(payload); err == nil {
			qrPayload = string(payloadBytes)
		} else {
			fmt.Fprintf(os.Stderr, "warning: unable to marshal QR payload, falling back to PSK only: %v\n", err)
		}
	}

	fmt.Println("Pre-Shared Key generated for this session:")
	if err := psk.PrintWithPayload(key, qrPayload, os.Stdout); err != nil {
		fatal(err)
	}

	if strings.TrimSpace(pskPNG) != "" {
		data, err := psk.EncodePayloadPNG(key, qrPayload, 256)
		if err != nil {
			fatal(err)
		}
		if err := os.WriteFile(pskPNG, data, 0o600); err != nil {
			fatal(err)
		}
		fmt.Printf("QR code PNG written to %s\n", pskPNG)
	}

	runner := &stream.FFMPEGRunner{
		Binary: ffmpegBin,
		Logger: logger,
	}
	worker := stream.NewWorker(runner, logger)

	opts := &server.Options{
		Logger: logger,
	}
	if strings.TrimSpace(tlsCert) != "" {
		opts.TLSCertFile = strings.TrimSpace(tlsCert)
		opts.TLSKeyFile = strings.TrimSpace(tlsKey)
	}

	listenAddr := strings.TrimSpace(addr)
	if listenAddr == "" {
		listenAddr = fmt.Sprintf("%s:%d", strings.TrimSpace(host), port)
	}

	srv, err := server.New(cfg, key, worker, opts)
	if err != nil {
		fatal(err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	logger.Info("server starting", slog.String("addr", listenAddr))
	if err := srv.ListenAndServe(ctx, listenAddr); err != nil && !errors.Is(err, context.Canceled) {
		logger.Error("server stopped", slog.String("error", err.Error()))
		os.Exit(1)
	}
	logger.Info("shutdown complete")
}

func runDetect(configPath string) {
	detector := detect.NewDetector(nil) // uses DefaultRunner
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	fmt.Println("Detecting available media devices...")

	cfg, warnings, err := detector.Detect(ctx)
	for _, w := range warnings {
		fmt.Fprintf(os.Stderr, "warning: %s\n", w)
	}
	if err != nil {
		fatal(err)
	}

	jsonData, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		fatal(fmt.Errorf("marshal config: %w", err))
	}

	// Write to config file
	if err := os.WriteFile(configPath, jsonData, 0o644); err != nil {
		fatal(fmt.Errorf("write config to %s: %w", configPath, err))
	}
	fmt.Printf("Detected %d device(s). Config written to %s\n", len(cfg.Devices), configPath)

	// Also print to stdout
	fmt.Println()
	fmt.Println(string(jsonData))
}

func fatal(err error) {
	fmt.Fprintf(os.Stderr, "fatal: %v\n", err)
	os.Exit(1)
}
