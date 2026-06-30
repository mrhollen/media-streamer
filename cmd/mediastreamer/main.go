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
		slog.Info("main: running in detect mode", slog.String("config_path", configPath))
		runDetect(configPath)
		return
	}

	slog.Info("main: initializing logger")
	logger := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelDebug}))
	slog.SetDefault(logger)

	slog.Info("main: loading configuration", slog.String("config_path", configPath))
	cfg, err := config.Load(configPath)
	if err != nil {
		slog.Error("main: failed to load configuration",
			slog.String("config_path", configPath),
			slog.String("error", err.Error()))
		fatal(err)
	}
	slog.Info("main: configuration loaded",
		slog.Int("device_count", len(cfg.Devices)))
	for _, d := range cfg.Devices {
		slog.Info("main: loaded device",
			slog.String("device_id", d.ID),
			slog.String("device_name", d.Name),
			slog.String("device_type", string(d.Type)),
			slog.String("ffmpeg_input", d.FFmpegInput))
	}

	if (strings.TrimSpace(tlsCert) == "") != (strings.TrimSpace(tlsKey) == "") {
		slog.Error("main: both --tls-cert and --tls-key must be provided")
		fatal(errors.New("both --tls-cert and --tls-key must be provided"))
	}

	var (
		key     string
		created bool
	)
	if strings.TrimSpace(pskFile) != "" {
		slog.Info("main: loading PSK from file", slog.String("psk_file", pskFile))
		key, created, err = psk.LoadOrCreate(pskFile, 0)
		if err != nil {
			slog.Error("main: failed to load or create PSK",
				slog.String("psk_file", pskFile),
				slog.String("error", err.Error()))
			fatal(err)
		}
		if created {
			slog.Info("main: generated new PSK", slog.String("psk_file", pskFile))
			fmt.Printf("Generated new PSK and stored in %s\n", pskFile)
		} else {
			slog.Info("main: loaded existing PSK", slog.String("psk_file", pskFile))
			fmt.Printf("Loaded PSK from %s\n", pskFile)
		}
	} else {
		slog.Info("main: generating new PSK (no psk-file specified)")
		key, err = psk.Generate(0)
		if err != nil {
			slog.Error("main: failed to generate PSK", slog.String("error", err.Error()))
			fatal(err)
		}
	}

	qrPayload := key
	if strings.TrimSpace(tlsCert) != "" {
		slog.Info("main: computing TLS certificate fingerprint",
			slog.String("tls_cert", tlsCert))
		fp, err := tlsutil.CertSHA256(tlsCert)
		if err != nil {
			slog.Error("main: failed to compute TLS certificate fingerprint",
				slog.String("error", err.Error()))
			fatal(err)
		}
		slog.Info("main: TLS certificate fingerprint computed",
			slog.String("fingerprint", fp))
		fmt.Printf("TLS certificate SHA-256 fingerprint: %s\n", fp)
		payload := map[string]string{
			"psk":          key,
			"tls_sha256":   strings.ReplaceAll(fp, ":", ""),
			"tls_friendly": fp,
		}
		if payloadBytes, err := json.Marshal(payload); err == nil {
			qrPayload = string(payloadBytes)
		} else {
			slog.Warn("main: unable to marshal QR payload, falling back to PSK only",
				slog.String("error", err.Error()))
			fmt.Fprintf(os.Stderr, "warning: unable to marshal QR payload, falling back to PSK only: %v\n", err)
		}
	}

	fmt.Println("Pre-Shared Key generated for this session:")
	if err := psk.PrintWithPayload(key, qrPayload, os.Stdout); err != nil {
		slog.Error("main: failed to print PSK", slog.String("error", err.Error()))
		fatal(err)
	}
	slog.Info("main: PSK printed to stdout")

	if strings.TrimSpace(pskPNG) != "" {
		slog.Info("main: encoding PSK as QR PNG", slog.String("output_path", pskPNG))
		data, err := psk.EncodePayloadPNG(key, qrPayload, 256)
		if err != nil {
			slog.Error("main: failed to encode PSK as QR PNG",
				slog.String("error", err.Error()))
			fatal(err)
		}
		if err := os.WriteFile(pskPNG, data, 0o600); err != nil {
			slog.Error("main: failed to write QR PNG file",
				slog.String("output_path", pskPNG),
				slog.String("error", err.Error()))
			fatal(err)
		}
		slog.Info("main: QR PNG written", slog.String("output_path", pskPNG))
		fmt.Printf("QR code PNG written to %s\n", pskPNG)
	}

	slog.Info("main: creating FFmpeg runner",
		slog.String("ffmpeg_binary", ffmpegBin))
	runner := &stream.FFMPEGRunner{
		Binary: ffmpegBin,
		Logger: logger,
	}
	slog.Info("main: creating stream worker")
	worker := stream.NewWorker(runner, logger)

	opts := &server.Options{
		Logger: logger,
	}
	if strings.TrimSpace(tlsCert) != "" {
		opts.TLSCertFile = strings.TrimSpace(tlsCert)
		opts.TLSKeyFile = strings.TrimSpace(tlsKey)
		slog.Info("main: TLS enabled",
			slog.String("tls_cert", opts.TLSCertFile),
			slog.String("tls_key", opts.TLSKeyFile))
	}

	listenAddr := strings.TrimSpace(addr)
	if listenAddr == "" {
		listenAddr = fmt.Sprintf("%s:%d", strings.TrimSpace(host), port)
	}
	slog.Info("main: determined listen address",
		slog.String("listen_addr", listenAddr),
		slog.String("host", host),
		slog.Int("port", port),
		slog.String("addr_flag", addr))

	slog.Info("main: constructing server")
	srv, err := server.New(cfg, key, worker, opts)
	if err != nil {
		slog.Error("main: failed to create server", slog.String("error", err.Error()))
		fatal(err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	logger.Info("main: server starting", slog.String("addr", listenAddr))
	if err := srv.ListenAndServe(ctx, listenAddr); err != nil && !errors.Is(err, context.Canceled) {
		logger.Error("main: server stopped with error", slog.String("error", err.Error()))
		os.Exit(1)
	}
	logger.Info("main: shutdown complete")
}

func runDetect(configPath string) {
	slog.Info("runDetect: creating detector")
	detector := detect.NewDetector(nil) // uses DefaultRunner
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	fmt.Println("Detecting available media devices...")
	slog.Info("runDetect: starting device detection",
		slog.Duration("timeout", 30*time.Second))

	cfg, warnings, err := detector.Detect(ctx)
	for _, w := range warnings {
		slog.Warn("runDetect: detection warning", slog.String("warning", w))
		fmt.Fprintf(os.Stderr, "warning: %s\n", w)
	}
	if err != nil {
		slog.Error("runDetect: device detection failed",
			slog.String("error", err.Error()))
		fatal(err)
	}
	slog.Info("runDetect: device detection complete",
		slog.Int("devices_found", len(cfg.Devices)),
		slog.Int("warnings", len(warnings)))

	jsonData, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		slog.Error("runDetect: failed to marshal config",
			slog.String("error", err.Error()))
		fatal(fmt.Errorf("marshal config: %w", err))
	}

	// Write to config file
	slog.Info("runDetect: writing config file", slog.String("path", configPath))
	if err := os.WriteFile(configPath, jsonData, 0o644); err != nil {
		slog.Error("runDetect: failed to write config file",
			slog.String("path", configPath),
			slog.String("error", err.Error()))
		fatal(fmt.Errorf("write config to %s: %w", configPath, err))
	}
	slog.Info("runDetect: config written successfully",
		slog.String("path", configPath),
		slog.Int("device_count", len(cfg.Devices)))
	fmt.Printf("Detected %d device(s). Config written to %s\n", len(cfg.Devices), configPath)

	// Also print to stdout
	fmt.Println()
	fmt.Println(string(jsonData))
}

func fatal(err error) {
	slog.Error("fatal: terminating", slog.String("error", err.Error()))
	fmt.Fprintf(os.Stderr, "fatal: %v\n", err)
	os.Exit(1)
}
