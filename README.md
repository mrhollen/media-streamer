# Media Streamer

Media Streamer is a lightweight Go server that turns local audio/video devices into secure network streams. It uses ffmpeg to capture and encode data, exposes a simple HTTP/WebSocket API, and protects access with a one-time pre-shared key (PSK) that is displayed as text and a QR code at startup.

## Features
- Stream audio or video from multiple devices concurrently using ffmpeg.
- Auto-detect available audio and video devices and generate a config file with `--detect`.
- Discover available devices over HTTPS and stream over secure WebSockets.
- Single PSK authentication for both REST and WebSocket flows, with optional QR code export.
- Optional TLS support with certificate fingerprinting for easy client verification.

## Prerequisites
- Go 1.25 or newer (`go version` should report ≥ 1.25).
- ffmpeg installed and available on your `PATH`.
- For device auto-detection: `v4l2-ctl` (from `v4l-utils`), `pactl` (PulseAudio/PipeWire), or `aplay` (ALSA). These are optional — without them, `--detect` will skip the corresponding device type with a warning.
- Access to the audio/video devices you plan to expose (Linux device files such as `/dev/video0`, PipeWire/PulseAudio monitors, etc.).
- Optional: TLS certificate and key (PEM files) if you want encrypted transport.

## Getting Started
### 1. Clone the repository
```bash
git clone git@github.com:mrhollen/media-streamer.git
cd media-streamer
```

### 2. Configure devices
Copy the sample configuration and adjust device entries for your hardware:
```bash
cp config.sample.json config.json
```

Each device entry tells ffmpeg how to capture and encode a stream:
```json
{
  "id": "webcam-high",
  "name": "Logitech C920 (High Res)",
  "type": "video",
  "ffmpeg_input": "/dev/video0",
  "ffmpeg_args": ["-f", "v4l2", "-framerate", "30", "-video_size", "1920x1080"],
  "output_codec": "libx264",
  "output_args": ["-preset", "ultrafast", "-tune", "zerolatency", "-f", "h264"]
}
```

- `id` must be unique; clients use it to request a stream.
- `ffmpeg_input`, `ffmpeg_args`, `output_codec`, and `output_args` map directly to ffmpeg command-line flags.
- Valid `type` values are `"video"` and `"audio"`; these control whether ffmpeg uses `-c:v` or `-c:a`.

### 2a. Auto-detect devices (alternative to manual configuration)
Instead of writing `config.json` by hand, you can let the server discover your devices automatically:

```bash
./mediastreamer --detect
```

This runs system probes (`v4l2-ctl` for video, `pactl` or `aplay` for audio) and writes a ready-to-use `config.json` with sensible defaults. The generated config is also printed to stdout.

To write the config to a specific path:
```bash
./mediastreamer --detect --config my-config.json
```

The detect mode does **not** start the server — it only generates the configuration file. Review the output, tweak any settings you like, then start the server normally.

If a detection tool is missing (e.g., no webcam for `v4l2-ctl`), a warning is printed on stderr and detection continues with the remaining device types.

### 3. Run the server
```bash
go run ./cmd/mediastreamer \
  --config config.json \
  --host 0.0.0.0 \
  --port 8080
```

The server prints a fresh PSK and renders a QR code in the terminal. Keep this key handy—clients must present it to authenticate. Common flags:

- `--ffmpeg /path/to/ffmpeg` to use a specific ffmpeg binary.
- `--psk-file /var/lib/media-streamer/psk.txt` to reuse a PSK across restarts (the file is created if missing).
- `--psk-png ./psk.png` to save the QR code as a PNG file (permissions default to `0600`).
- `--tls-cert ./tls/dev.crt --tls-key ./tls/dev.key` to enable HTTPS/WSS. When TLS is active, the console shows the certificate SHA-256 fingerprint so clients can pin it.

### 4. Talk to the API
1. Request the device catalog (replace `YOUR_PSK` with the value printed at startup):
    ```bash
    curl -H "Authorization: Bearer YOUR_PSK" http://localhost:8080/devices
    ```
2. Connect a WebSocket client such as `wscat` or a browser. The first message sent on the socket must be the PSK; once accepted, binary frames start streaming the encoded data:
    ```bash
    wscat -c ws://localhost:8080/stream/webcam-high
    # send: YOUR_PSK
    ```

### 5. Build a binary (optional)
```bash
go build -o bin/mediastreamer ./cmd/mediastreamer
```

Run the compiled binary with the same flags described above.

## Command-Line Reference
| Flag | Default | Description |
|------|---------|-------------|
| `--detect` | `false` | Auto-detect devices and generate a config file (does not start the server). |
| `--config` | `config.json` | Path to JSON config describing devices. |
| `--host` | `0.0.0.0` | Interface to bind when `--addr` is empty. |
| `--port` | `8080` | Port to use when `--addr` is empty. |
| `--addr` | *(blank)* | Full listen address, overrides host/port. |
| `--ffmpeg` | *(ffmpeg on PATH)* | Path to ffmpeg binary. |
| `--psk-png` | *(blank)* | Write QR code PNG to this file. |
| `--psk-file` | *(blank)* | Load PSK from file or create a new one. |
| `--tls-cert` / `--tls-key` | *(blank)* | PEM files enabling HTTPS/WSS. Both must be supplied together. |

## TLS Quick Start (Optional)
Generate a self-signed certificate for local testing (valid for 365 days):
```bash
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout tls/dev.key \
  -out tls/dev.crt \
  -subj "/CN=localhost"
```

Start the server with `--tls-cert tls/dev.crt --tls-key tls/dev.key`. The console prints a fingerprint that you can compare on the client side to prevent MITM attacks.

## Project Layout
- `cmd/mediastreamer`: Application entry point, flag parsing, and startup wiring.
- `internal/config`: Config parsing and validation helpers.
- `internal/detect`: Device auto-detection using `v4l2-ctl` (video) and `pactl`/`aplay` (audio).
- `internal/psk`: PSK generation, QR printing, and persistence utilities.
- `internal/server`: HTTP and WebSocket handlers plus authentication checks.
- `internal/stream`: ffmpeg runner abstraction and streaming worker.
- `internal/tlsutil`: Certificate fingerprint utilities.
- `config.sample.json`: Example device definitions to copy into `config.json`.

## Testing
Run the full Go test suite:
```bash
go test ./...
```

Tests cover configuration validation, PSK helpers, TLS fingerprinting, and stream coordination logic. Resolve any reported issues before deploying changes.

## Troubleshooting
- **PSK rejected**: Ensure you send the exact key, without whitespace, and that the server was started with the same `psk-file` if you expect persistence.
- **ffmpeg errors**: Watch the server logs—stderr from ffmpeg is mirrored as warnings. Adjust device `ffmpeg_args` and confirm the input device exists.
- **WebSocket closes immediately**: The client must send a text frame containing only the PSK as the first message; binary frames prior to auth are rejected.
- **TLS handshake fails**: Confirm the certificate and key paths are correct and the files are readable by the server process.

Happy streaming!
