# Data Models & API Integration Specification

## Summary

This document defines the data models, API integration, local storage, and state management for the Media Streamer mobile client. It provides the foundation for implementing the UI/UX specifications.

## Table of Contents

- [Data Models](#data-models)
  - [Server Model](#server-model)
  - [Device Model](#device-model)
  - [ServerStatus](#serverstatus)
  - [DeviceType](#devicetype)
- [API Integration](#api-integration)
- [Local Storage](#local-storage)
- [State Management](#state-management)

---

## Data Models

### Server Model

```dart
class Server {
  String id;              // Unique local ID (UUID)
  String address;         // e.g., "192.168.1.100:8080"
  String name;            // User-assigned name or derived from hostname
  String psk;             // Pre-Shared Key for authentication
  String? tlsFingerprint; // Optional TLS certificate SHA-256 fingerprint
  bool isTls;             // Whether to use wss:// vs ws://
  ServerStatus status;    // connected, connecting, offline
  List<Device> devices;   // Cached device list
  DateTime? lastConnected;
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| id | String | Unique local identifier (UUID v4) |
| address | String | Server address with port (e.g., "192.168.1.100:8080") |
| name | String | User-assigned name; fallback to hostname/IP if empty |
| psk | String | Pre-Shared Key for WebSocket authentication |
| tlsFingerprint | String? | SHA-256 fingerprint of TLS certificate |
| isTls | bool | Use wss:// (true) or ws:// (false) for WebSocket |
| status | ServerStatus | Current connection status |
| devices | List<Device> | Cached list of available devices |
| lastConnected | DateTime? | Timestamp of last successful connection |

**Methods:**
- `fromJson(Map<String, dynamic> json)`: Convert from JSON
- `toJson()`: Convert to JSON
- `getDisplayName()`: Return display name (name or address)

### Device Model

```dart
class Device {
  String id;              // From server API
  String name;            // From server API (e.g., "Logitech C920")
  DeviceType type;        // video or audio
  String serverId;        // Reference to parent server
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| id | String | Unique device identifier from server |
| name | String | Device name from server API |
| type | DeviceType | Video or audio device |
| serverId | String | Parent server ID (local UUID) |

**Methods:**
- `fromJson(Map<String, dynamic> json)`: Convert from JSON
- `toJson()`: Convert to JSON
- `getIcon()`: Return icon type string for UI

### ServerStatus Enum

```dart
enum ServerStatus {
  offline,    // Initial state, never connected
  connecting, // Attempting to connect
  connected,  // Successfully connected
}
```

**Usage:**
- Set to `connecting` when checking status
- Set to `connected` when successful
- Set to `offline` on connection failure

### DeviceType Enum

```dart
enum DeviceType {
  video,  // Camera/Webcam
  audio,  // Microphone
}
```

**UI Mapping:**
- `video` → Camera icon
- `audio` → Speaker icon

---

## API Integration

### Base Configuration

```dart
class ApiConfig {
  static const String baseUrl = "ws://"; // or "wss://" based on isTls
  static const int httpTimeout = 10000;  // 10 seconds
  static const int wsTimeout = 10000;    // 10 seconds
  static const String headerAuth = "Authorization";
}
```

### HTTP Endpoints

#### GET /devices

**Purpose:** Fetch list of available devices from server

**Request:**
```
GET /devices
Authorization: Bearer <PSK>
```

**Response:**
```json
[
  {
    "id": "device-123",
    "name": "Logitech C920",
    "type": "video"
  },
  {
    "id": "device-456",
    "name": "Built-in Microphone",
    "type": "audio"
  }
]
```

**Error Responses:**
- `401`: Invalid PSK
- `404`: Server not found
- `500`: Server error
- `NetworkError`: Network unavailable

**Usage:**
- Called when loading Server List or Device List
- Cached locally after successful fetch
- Refreshed on pull-to-refresh

### WebSocket Endpoint

#### GET /stream/{deviceId}

**Purpose:** Establish live stream connection

**Connection:**
```
ws://<server-address>:<port>/stream/<device-id>
```

**Message Flow:**

1. **Authentication (First Message):**
   ```
   Send: "Bearer <PSK>"  (text frame)
   Receive: OK or error
   ```

2. **Stream Data (Subsequent Messages):**
   - Binary frames
   - Video: H.264 format
   - Audio: Opus format

**Timeouts:**
- Connection timeout: 10 seconds
- Authentication timeout: 10 seconds

**Error Handling:**
- `401`: Invalid PSK → Show error on Stream Viewer
- `404`: Device not found → Show error on Stream Viewer
- `500`: Server error → Show error on Stream Viewer
- Connection closed → Show disconnected state

**WebSocket Manager:**
- Single WebSocket connection per device
- Connection lifecycle managed by `StreamProvider`
- Auto-reconnect on unexpected close (optional)

---

## Local Storage

### Storage Strategy

**Package:** `shared_preferences`

**Purpose:** Persist server list and configuration

**Data Structure:**
```dart
String key = 'servers';
Value type = List<String> (JSON-encoded)
```

**Format:**
```json
[
  {
    "id": "uuid-1",
    "address": "192.168.1.100:8080",
    "name": "Home Server",
    "psk": "secret-key",
    "tlsFingerprint": "abc123...",
    "isTls": false,
    "status": "connected",
    "devices": [{"id": "...", "name": "...", "type": "video"}],
    "lastConnected": "2026-06-25T10:30:00Z"
  },
  ...
]
```

### Storage Operations

**Save Server:**
```dart
void saveServer(Server server) {
  final servers = await _getServers();
  servers.add(server.toJson());
  await _saveServers(servers);
}
```

**Load Servers:**
```dart
Future<List<Server>> getServers() async {
  final jsonList = await _getStringList('servers');
  if (jsonList == null) return [];
  return jsonList.map((json) => Server.fromJson(json)).toList();
}
```

**Remove Server:**
```dart
Future<void> removeServer(String serverId) async {
  final servers = await _getServers();
  servers.removeWhere((s) => s.id == serverId);
  await _saveServers(servers);
}
```

**Clear All:**
```dart
Future<void> clearServers() async {
  await _removeKey('servers');
}
```

### Security Notes

**PSK Storage:**
- Stored in plain text
- User responsibility for device security
- No encryption (keep dependencies minimal)

**Recommendations:**
- Advise users to protect their devices physically
- Consider PSK rotation for security
- Warn users about network security

---

## State Management

### Architecture

**Package:** None (built-in Flutter)

**Pattern:** `ChangeNotifier`

**Provider:** `ServerProvider`

### ServerProvider

```dart
class ServerProvider extends ChangeNotifier {
  List<Server> _servers = [];
  Map<String, ServerStatus> _serverStatuses = {};
  Server? _activeStreamServer;
  String? _activeStreamDeviceId;
  bool _isLoading = false;

  // Properties
  List<Server> get servers => List.unmodifiable(_servers);
  Map<String, ServerStatus> get serverStatuses => Map.unmodifiable(_serverStatuses);
  bool get hasActiveStream => _activeStreamServer != null;
  bool get isLoading => _isLoading;

  // Methods
  Future<void> loadServers();
  Future<void> checkServerStatus(String serverId);
  Future<void> addServer(Server server);
  Future<void> removeServer(String serverId);
  Future<void> refreshDeviceList(String serverId);
  void startStream(String serverId, String deviceId);
  void stopStream();
  void updateServerStatus(String serverId, ServerStatus status);
}
```

### State Transitions

```
Initial State
  ↓
loadServers() called
  ↓
_servers = []
_isLoading = true
notifyListeners()
  ↓
Servers loaded
  ↓
_servers = [Server objects]
_isLoading = false
notifyListeners()
```

### Stream Management

```
User taps device
  ↓
ServerProvider.startStream(serverId, deviceId)
  ↓
_showConnectingState()
_notifyListeners()
  ↓
WebSocket connects
  ↓
_authenticate()
  ↓
_streamStarted()
  ↓
_setActiveStream(serverId, deviceId)
_notifyListeners()
  ↓
User navigates away
  ↓
ServerProvider.stopStream()
  ↓
_closeWebSocket()
_clearActiveStream()
_notifyListeners()
```

### Mini-Player State

**Trigger:** `hasActiveStream` becomes true

**Update:** `ServerProvider` notifies listeners when stream state changes

**UI:**
- Server List: Mini-player pill visible when `hasActiveStream`
- Device List: Mini-player pill visible when `hasActiveStream`

### Error Handling

**Network Errors:**
- Caught at API layer
- Propagated to UI layer
- UI shows inline error banner

**WebSocket Errors:**
- Caught in `StreamProvider`
- Stream state transitions to Error/Disconnected
- UI shows error state on Stream Viewer

---

## Implementation Notes

### Dependencies

**Required:**
- `shared_preferences`: Local storage
- `web_socket_channel`: WebSocket client (if not using package)
- `camera` / `qr_code_scanner`: QR scanning
- `video_player`: Video playback
- `permission_handler`: Camera permissions

**Optional:**
- `flutter_icon`: Device type icons
- `audio_level`: Audio visualization

### Best Practices

1. **Separation of Concerns:**
   - Models: Pure data classes
   - API: Network layer
   - State: `ServerProvider`
   - UI: Widgets

2. **Error Handling:**
   - Catch errors at appropriate layer
   - Don't swallow errors
   - Provide user feedback

3. **Performance:**
   - Use `ListView.builder` for large lists
   - Lazy load device lists
   - Cache device lists after fetch

4. **Memory:**
   - Close WebSocket on navigation away
   - Dispose camera controller when modal dismissed
   - Clear cached data when removing servers

5. **Testing:**
   - Unit test models
   - Mock API calls
   - Test state transitions
