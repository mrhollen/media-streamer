# Media Streamer - Project Review

## Overview
Media Streamer is a lightweight Go server that captures audio/video from local devices (webcams, microphones, system audio) and streams them over secure WebSocket connections to authorized clients. It uses ffmpeg for real-time transcoding and encoding.

## Architecture
- **Single-binary server** written in Go
- **PSK-based authentication** (Pre-Shared Key)
- **FFmpeg subprocess** for media capture and encoding
- **WebSocket binary streaming** for media delivery
- **QR code onboarding** for easy client setup

## Key Components
| Component | Path | Purpose |
|-----------|------|---------|
| Entry Point | `cmd/mediastreamer/main.go` | CLI flags, startup, TLS config |
| Config | `internal/config/` | JSON config parsing & validation |
| PSK | `internal/psk/` | Key generation, QR rendering |
| Server | `internal/server/` | HTTP & WebSocket handlers |
| Stream | `internal/stream/` | FFmpeg runner, data worker |
| TLS | `internal/tlsutil/` | Certificate fingerprinting |

## API Endpoints

### GET `/devices`
- **Auth**: `Authorization: Bearer <PSK>`
- **Response**: JSON array of devices
```json
[
  { "id": "webcam-high", "name": "Logitech C920", "type": "video" },
  { "id": "system-audio", "name": "Desktop Audio", "type": "audio" }
]
```

### GET `/stream/{deviceID}` (WebSocket)
- **Protocol**: WebSocket upgrade
- **Auth**: First text message must contain the PSK
- **Data**: Binary WebSocket frames (raw encoded media - H.264, Opus, etc.)
- **Close Codes**: 1000 (normal), 403 (bad PSK), 404 (bad device), 1011 (error)

## Data Models

### Device
```json
{
  "id": "unique-id",
  "name": "Human Readable Name",
  "type": "video" | "audio",
  "ffmpeg_input": "/dev/video0",
  "ffmpeg_args": ["-f", "v4l2", "-framerate", "30"],
  "output_codec": "libx264",
  "output_args": ["-preset", "ultrafast", "-f", "h264"]
}
```

### QR Code Payload
- **Simple (no TLS)**: Raw PSK string
- **With TLS**: JSON `{"psk": "...", "tls_sha256": "...", "tls_friendly": "..."}`

## Authentication Flow
1. Server generates 32-byte random PSK (Base64 URL-safe)
2. Server displays PSK + ASCII QR code in terminal
3. Client scans QR → extracts PSK
4. Client uses PSK for HTTP Bearer auth and WebSocket first message

## Client Requirements
1. Scan QR code to obtain PSK (and optionally TLS fingerprint)
2. Store server connection info (host, port, PSK, TLS cert path)
3. GET `/devices` to list available streams
4. WebSocket connect to `/stream/{deviceID}`
5. Send PSK as first text message
6. Receive and decode binary media frames

## Dependencies
- Go 1.25.3+
- ffmpeg (external binary)
- `nhooyr.io/websocket` - WebSocket library
- `github.com/mdp/qrterminal/v3` - ASCII QR codes
- `github.com/skip2/go-qrcode` - PNG QR codes

## No Existing Frontend
The server has NO built-in frontend. It is designed to be consumed by external clients (mobile apps, web apps, custom clients).
