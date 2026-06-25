# Media Streamer Client

Mobile client for the Media Streamer Go server. This Flutter application enables users to discover, connect to, and stream media from Media Streamer servers via QR codes or manual entry.

## Summary

The Media Streamer Client is a Flutter-based mobile application that provides a seamless interface for connecting to Media Streamer servers, browsing available devices (cameras, microphones), and streaming live media content. The app features QR code-based server discovery, persistent server management, dark theme UI, and a mini-player for quick stream access.

**Table of Contents**

1. [Features](#features)
2. [Screenshots](#screenshots)
3. [Prerequisites](#prerequisites)
4. [Quick Start](#quick-start)
5. [How It Works](#how-it-works)
6. [QR Code Format](#qr-code-format)
7. [Project Structure](#project-structure)
8. [Dependencies](#dependencies)
9. [Development](#development)
10. [Future Enhancements](#future-enhancements)
11. [License](#license)

---

## Features

- **QR Code Server Discovery** — Scan QR codes to instantly connect to Media Streamer servers
- **Manual Server Entry** — Add servers by manually entering host, port, and PSK
- **Device Browsing** — View and select video cameras and audio microphones from connected servers
- **Live Streaming** — Real-time WebSocket streaming of media frames
- **Dark Theme UI** — Modern Material 3 design with dark theme
- **Mini-Player** — Persistent stream indicator at the bottom of all screens
- **Server Management** — Rename and remove saved servers via long-press context menu
- **Connection Status** — Visual indicators for server connection states
- **Persistent Storage** — Servers saved locally using SharedPreferences

---

## Screenshots

Screenshots coming soon

---

## Prerequisites

### Flutter SDK

- Flutter SDK version: `^3.11.0-30.0.dev` or higher
- Dart SDK version: `^3.11.0` or higher

### Media Streamer Server

- Go-based Media Streamer server must be running and accessible
- Server must expose devices via HTTP API at `/devices` endpoint
- Server must support WebSocket streaming at `/stream/{deviceId}` endpoint
- Authentication via Pre-Shared Key (PSK) is required

### Development Environment

- macOS, Windows, or Linux development machine
- Android Studio, IntelliJ IDEA, or VS Code with Flutter extensions
- Android emulator or physical Android device
- iOS simulator or physical iOS device (for iOS builds)

---

## Quick Start

1. **Clone the repository** (if not already done)
   ```bash
   git clone <repository-url>
   cd media-streamer/mobile-client
   ```

2. **Get dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the application**
   ```bash
   flutter run
   ```

4. **Add a server**
   - Tap the QR scanner button (bottom-right) or use manual entry
   - Scan a QR code or enter server details manually
   - Server will be validated and added to your saved list

5. **Browse and stream**
   - Tap a server to view its devices
   - Tap a device (camera or microphone) to start streaming

---

## How It Works

### User Flow

1. **Scan QR → Add Server**
   - User scans a QR code containing server configuration
   - QR parser extracts PSK, host, port, and optional TLS fingerprint
   - App validates server by fetching device list via HTTP API
   - Server is saved to local storage with connection status

2. **Browse Devices**
   - User taps a server card on the main screen
   - App fetches device list from server API (if not cached)
   - Device list displays video cameras and audio microphones

3. **Start Stream**
   - User taps a device to begin streaming
   - App establishes WebSocket connection to `/stream/{deviceId}`
   - PSK is sent as first frame for authentication
   - Binary media frames received via WebSocket are processed

4. **Mini-Player**
   - Active stream displays a pill-shaped widget at the bottom of all screens
   - Shows device name, server name, and streaming indicator
   - Tap to open full stream viewer; stop button ends the stream

### Technical Flow

```
User Action
    ↓
UI Layer (Screens/Widgets)
    ↓
State Management (ServerProvider)
    ↓
Services (ApiService, StreamService)
    ↓
Network (HTTP, WebSocket)
    ↓
Server Response
    ↓
State Update → UI Rebuild
```

---

## QR Code Format

QR codes contain JSON data with the following structure:

```json
{
  "psk": "your-pre-shared-key",
  "host": "192.168.1.100",
  "port": 8080,
  "tls_sha256": "sha256-fingerprint-here"
}
```

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `psk` | string | Yes | Pre-Shared Key for authentication |
| `host` | string | No | Server hostname or IP address |
| `port` | integer | No | Server port (defaults to 8080 for HTTP, 443 for TLS) |
| `tls_sha256` | string | No | TLS fingerprint (indicates TLS should be used) |

### Alternatives

- **Plain text PSK**: QR code can contain just the PSK string. Manual host/port entry dialog will appear.
- **TLS Detection**: Presence of `tls_sha256` field indicates TLS should be used for connection.

---

## Project Structure

```
mobile-client/
├── android/                    # Android platform files
├── ios/                        # iOS platform files
├── lib/
│   ├── app.dart               # Root widget (app entry)
│   ├── main.dart              # App initialization & provider setup
│   ├── models/
│   │   ├── device.dart        # Device model (video/audio)
│   │   └── server.dart        # Server model with status enum
│   ├── providers/
│   │   └── server_provider.dart  # State management (ChangeNotifier)
│   ├── screens/
│   │   ├── device_list_screen.dart   # Device browser
│   │   ├── qr_scanner_screen.dart    # QR scanner
│   │   ├── server_list_screen.dart   # Main server list
│   │   └── stream_viewer_screen.dart # Stream viewer
│   ├── services/
│   │   ├── api_service.dart   # HTTP client for server API
│   │   ├── stream_service.dart # WebSocket stream manager
│   │   └── storage_service.dart # Local persistence
│   ├── theme/
│   │   └── app_theme.dart     # Material 3 theme configuration
│   ├── utils/
│   │   └── qr_parser.dart     # QR code JSON parser
│   └── widgets/
│       ├── connection_status_dot.dart    # Status indicator
│       ├── device_row.dart       # Device list row
│       ├── mini_player.dart      # Active stream pill
│       └── server_card.dart      # Server list card
├── test/
│   └── widget_test.dart       # Widget tests
├── pubspec.yaml               # Dependencies & metadata
└── analysis_options.yaml      # Linting rules
```

---

## Dependencies

### Production Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter` | SDK | Framework |
| `cupertino_icons` | ^1.0.8 | iOS-style icons |
| `http` | ^1.2.0 | HTTP requests to server API |
| `web_socket_channel` | ^3.0.0 | WebSocket connections for streaming |
| `shared_preferences` | ^2.2.0 | Local server list persistence |
| `mobile_scanner` | ^5.0.0 | QR code camera scanning |
| `uuid` | ^4.3.0 | Generate unique server IDs |
| `provider` | ^6.1.2 | State management |

### Development Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_test` | SDK | Widget testing |
| `flutter_lints` | ^6.0.0 | Linting rules |

---

## Development

### Running the Application

```bash
# Get dependencies
flutter pub get

# Run on connected device/emulator
flutter run

# Run with specific platform
flutter run -d <device-id>

# Run in debug mode
flutter run --debug

# Run with profile mode
flutter run --profile
```

### Testing

```bash
# Run all tests
flutter test

# Run widget tests
flutter test test/widget_test.dart

# Run with coverage
flutter test --coverage
```

### Code Analysis

```bash
# Analyze code for issues
flutter analyze

# Format code
flutter format lib/

# Check for lints
flutter analyze --no-pub
```

### Building

```bash
# Build APK (Android)
flutter build apk --release

# Build App Bundle (Android)
flutter build appbundle --release

# Build IPA (iOS)
flutter build ios --release
```

### Hot Reload

While the app is running:

```bash
# Edit a file and press 'r' in terminal
# Or use the hot reload button in IDE
```

---

## Future Enhancements

### Video/Audio Decoding

- Integrate `video_player` package for H.264 video playback
- Add audio decoding for Opus streams
- Display actual media instead of animated indicators

### Fullscreen Support

- Native fullscreen mode on Android/iOS
- Picture-in-picture support
- Background stream handling

### Performance Optimization

- Implement video frame caching
- Add stream buffering
- Optimize WebSocket reconnection logic

### User Experience

- Add server grouping/folders
- Implement server search/filter
- Add server health monitoring
- Streaming statistics (bitrate, FPS, latency)

### Security

- TLS certificate pinning
- PSK encryption at rest
- Biometric authentication for app access

### Platform Support

- Tablet layout optimization
- Foldable device support
- WearOS integration
- Fuchsia support

---

## License

Copyright (c) 2024 Media Streamer Team.

Licensed under the MIT License.

See the main repository for full license details.
