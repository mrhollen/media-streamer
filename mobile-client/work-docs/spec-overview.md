# Media Streamer Mobile Client - UI/UX Specifications

## Summary

This document contains comprehensive UI/UX specifications for the Media Streamer mobile Flutter app, a client for a Go media streaming server that exposes AV devices (webcams, microphones) over the network. The specs cover app overview, design principles, navigation model, and detailed specifications for all major screens.

## Table of Contents

- [App Overview](#app-overview)
- [Design Principles](#design-principles)
- [Navigation Model](#navigation-model)
- [Screen Specifications](#screen-specifications)
  - [Server List](#server-list)
  - [Device List](#device-list)
  - [Stream Viewer](#stream-viewer)
  - [QR Scanner](#qr-scanner)
- [Data Models & API](#data-models-api)

---

## App Overview

**Purpose:** Mobile client for a Go media streaming server that exposes AV devices (webcams, mics) over the network.

**Target Users:** People who want to remotely view their cameras/audio from a phone.

---

## Design Principles

1. **Stream-first:** The live stream is the star. UI chrome is minimal and gets out of the way.

2. **Dark by default:** Streaming typically happens in dim environments.

3. **Simple navigation:** Stack-based. No tabs, no drawers. Server List → Device List → Stream Viewer.

4. **Mini-player persistence:** When a stream is active, a mini-player pill appears at the bottom of browsing screens.

5. **Gesture-driven:** Swipe back, pull-to-refresh, long-press for context menus.

6. **Graceful degradation:** Connection errors are inline, not modal alerts. Loading is invisible when possible.

---

## Navigation Model

Stack navigation with 3 main screens:

1. **Server List (root)** — list of saved servers
2. **Device List** — pushed on top of server list when a server is tapped
3. **Stream Viewer** — pushed on top when a device is tapped

**Modal:**
- **QR Scanner** — presented as a full-screen modal dialog (showModalBottomSheet or showAdaptiveDialog)

---

## Screen Specifications

### Server List

**Location:** Root/home screen of the app

**Layout:**
- **App bar:** Title "Media Streamer" on the left. No trailing actions.
- **Body:** Vertically scrollable list of server cards
  - Each card shows:
    - Server name (or IP if unnamed)
    - Connection status dot (green=connected, amber=connecting, gray=offline)
    - Device count badge
  - Cards have subtle elevation and rounded corners
  - Tapping a card navigates to that server's Device List
  - Long-pressing a card shows a context menu: Rename, Remove
- **Empty state (no servers):** Centered content with an icon, "No servers yet" text, and a prominent "Add Server" button
- **FAB (floating action button):** "+" icon in the bottom-right corner, opens the QR Scanner modal
- **Mini-player pill:** When a stream is active, a compact pill appears at the bottom of the screen (above the FAB area) showing:
  - Device name
  - Server name
  - Small play/pause indicator
  - Stop button
  - Tapping the pill navigates to the Stream Viewer

**Interactions:**
- **Pull-to-refresh:** Re-checks connection status of all servers
- **Swipe on server card:** Not needed — use long-press for context menu
- **Tap server card:** Pushes Device List screen
- **Tap FAB:** Presents QR Scanner modal

**Loading state:** Skeleton cards with shimmer animation while servers are being checked

**Error state:** If network is unavailable, show a banner at the top: "No network connection" with a retry button

---

### Device List

**Location:** Pushed on top of Server List when a server is tapped

**Layout:**
- **App bar:** Back button on left, server name as title, connection status dot on right
- **Body:** Vertically scrollable list of device rows
  - Each row shows:
    - Device type icon (camera for video, speaker for audio)
    - Device name
    - Type label ("Video" or "Audio")
  - Rows are tappable — tapping opens the Stream Viewer
  - Device rows have a clean, minimal design with subtle dividers
- **Empty state:** "No devices available" with a refresh button

**Interactions:**
- **Pull-to-refresh:** Re-fetches device list from server
- **Tap device row:** Pushes Stream Viewer screen, begins connecting to WebSocket stream
- **Long-press device row:** Context menu with "Copy device ID"

**Loading state:** Skeleton rows with shimmer animation

**Error state:** If server is unreachable, show a banner at the top: "Server is offline" with a reconnect button. Device rows appear dimmed/disabled.

---

### Stream Viewer

**Location:** Pushed on top of Device List when a device is tapped. This is the primary screen of the app.

**Layout:**
- **NO visible app bar or chrome by default.** The stream fills the entire screen.
- **Controls overlay:** Appears on tap, auto-hides after 3 seconds of inactivity. Controls include:
  - **Top area:** Device name and server name labels, back button (top-left)
  - **Bottom area:** Stop button (center), device type indicator
- **Video stream:** Full-screen video player. Video fills the screen maintaining aspect ratio (letterbox or crop).
- **Audio stream:** Centered device name, large play/stop button, subtle audio level visualization (animated bars or waveform).

**States:**
- **Connecting:** Minimal centered spinner with "Connecting..." text
- **Playing:** Full stream with tap-to-reveal controls
- **Error:** Centered error card with device name, error message, and "Retry" button
- **Disconnected:** Same as error, with "Connection lost" message and "Reconnect" button

**Interactions:**
- **Tap anywhere:** Toggle controls overlay visibility
- **Swipe down from top:** Go back to Device List, stop the stream
- **Back button:** Same as swipe down
- **Stop button:** Stop the stream, go back to Device List

**Behavior:**
- When user navigates away (back), the stream is stopped and WebSocket is closed
- If stream disconnects unexpectedly, show error state in-place (don't navigate away)
- Retry button re-attempts the WebSocket connection

---

### QR Scanner

**Location:** Presented as a full-screen modal dialog from the Server List FAB

**Layout:**
- **Camera preview:** Fills the entire screen
- **Scanning overlay:** Centered rounded rectangle with corner brackets, guiding the user where to aim
- **Instruction text above the overlay:** "Point your camera at the QR code"
- **Cancel button:** Top-left corner
- **"Enter manually" link:** At the bottom for users who prefer typing

**Flow:**
1. User taps FAB → Scanner modal opens, camera activates
2. User points camera at QR code from server terminal
3. QR code is detected and parsed
4. Camera freezes, a confirmation card slides up from the bottom showing:
   - Server address (e.g., "192.168.1.100:8080")
   - TLS indicator (if TLS fingerprint was in the QR payload)
   - "Connecting..." state as the app validates the connection
5. On success: Card shows "Connected", modal dismisses, server is added to the list, Device List is pushed for the new server
6. On failure: Card shows error message with "Try Again" and "Cancel" buttons

**Manual entry mode:**
- Simple form with fields: Server Address, PSK, optional TLS Fingerprint
- "Save & Connect" button validates and tests the connection
- On success, server is added and Device List is pushed

**Error handling:**
- **Camera permission denied:** Show explanation and "Open Settings" button
- **Invalid QR code:** Brief inline message "Could not read server details" — continue scanning
- **Connection failed:** Clear error message with retry option

---

## Data Models & API

### Server Model

```
Server {
  id: String              // Unique local ID (UUID)
  address: String         // e.g., "192.168.1.100:8080"  
  name: String            // User-assigned name or derived from hostname
  psk: String             // Pre-Shared Key for authentication
  tlsFingerprint: String? // Optional TLS certificate SHA-256 fingerprint
  isTls: bool             // Whether to use wss:// vs ws://
  status: ServerStatus    // connected, connecting, offline
  devices: List<Device>   // Cached device list
  lastConnected: DateTime?
}
```

### Device Model

```
Device {
  id: String              // From server API
  name: String            // From server API (e.g., "Logitech C920")
  type: DeviceType        // video or audio
  serverId: String        // Reference to parent server
}
```

### API Integration

- **GET /devices:** HTTP request with `Authorization: Bearer <PSK>` header. Returns JSON array of `{id, name, type}`.
- **GET /stream/{deviceId}:** WebSocket connection. First message must be the PSK as a text frame. Subsequent messages are binary frames (H.264 video or Opus audio).
- **Connection timeout:** 10 seconds for HTTP, 10 seconds for WebSocket auth.
- **Error handling:** 401 = invalid PSK, 404 = device not found, 500 = server error.

### Local Storage

- Use `shared_preferences` for simple key-value storage of servers list
- Servers are stored as JSON-encoded list
- PSKs are stored in plain text (user responsibility for device security)
- No encryption of stored data (keep dependencies minimal)

### State Management

- Use `ChangeNotifier` for simple, built-in state management
- One `ServerProvider` ChangeNotifier that manages the list of servers, their connection states, and active streams
- No external state management packages (Riverpod, Bloc, Provider) — keep it simple
