# Architecture

Technical architecture documentation for the Media Streamer Client Flutter application.

## Summary

This document describes the architectural decisions, layered structure, data flow patterns, and key design choices of the Media Streamer Client. The app follows a clean architecture approach with clear separation between UI, state management, services, and models.

**Table of Contents**

1. [High-Level Architecture](#high-level-architecture)
2. [Layer Breakdown](#layer-breakdown)
3. [Data Flow](#data-flow)
4. [Stream Flow](#stream-flow)
5. [Navigation Flow](#navigation-flow)
6. [State Management](#state-management)
7. [Error Handling](#error-handling)
8. [Persistence](#persistence)
9. [Key Design Decisions](#key-design-decisions)

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         USER INTERFACE                               │
├─────────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │ Server List  │  │Device List   │  │Stream Viewer │              │
│  │   Screen     │  │  Screen      │  │   Screen     │              │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘              │
│         │                 │                 │                        │
│         └─────────────────┴─────────────────┘                        │
│                              │                                       │
│                        ┌─────▼─────┐                                 │
│                        │ Widgets   │                                 │
│                        │& Screens  │                                 │
│                        └─────┬─────┘                                 │
└──────────────────────────────┼──────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│                        STATE MANAGEMENT                              │
├─────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    ServerProvider                            │    │
│  │              (extends ChangeNotifier)                        │    │
│  │                                                              │    │
│  │  • servers: List<Server>                                    │    │
│  │  • activeStreamServer: Server?                              │    │
│  │  • activeStreamDevice: Device?                              │    │
│  │  • streamState: StreamConnectionState                       │    │
│  │  • streamSession: StreamSession?                            │    │
│  │  • bytesReceived: int                                       │    │
│  │  • _deviceCache: Map<String, List<Device>>                  │    │
│  │  • _statusOverrides: Map<String, ServerStatus>              │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              │                                       │
│         ┌────────────────────┼────────────────────┐                 │
│         │                    │                    │                 │
│         ▼                    ▼                    ▼                 │
└──────────────────────────────────────────────────────────────────────┘
                              │
┌──────────────────────────────▼──────────────────────────────────────┐
│                        SERVICES                                      │
├─────────────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │   ApiService     │  │  StreamService   │  │ StorageService   │  │
│  │                  │  │                  │  │                  │  │
│  │ • fetchDevices() │  │ • startStream()  │  │ • loadServers()  │  │
│  │ • pingServer()   │  │ • stopStream()   │  │ • saveServers()  │  │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘  │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│                        MODELS                                        │
├─────────────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐  ┌──────────────────┐                         │
│  │    Server        │  │     Device       │                         │
│  │                  │  │                  │                         │
│  │ • id: String     │  │ • id: String     │                         │
│  │ • name: String   │  │ • name: String   │                         │
│  │ • address: String│  │ • type: DeviceType│                         │
│  │ • psk: String    │  │                  │                         │
│  │ • devices: List<Device>│                │                         │
│  │ • status: ServerStatus│                │                         │
│  └──────────────────┘  └──────────────────┘                         │
└──────────────────────────────────────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│                        EXTERNAL                                     │
├─────────────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐  ┌──────────────────┐                         │
│  │    HTTP          │  │  WebSocket       │                         │
│  │   Client         │  │  Channel         │                         │
│  │                  │  │                  │                         │
│  │  GET /devices    │  │  ws://host/stream│                         │
│  └──────────────────┘  │  /{deviceId}     │                         │
│                        └──────────────────┘                         │
│  ┌──────────────────┐                                              │
│  │ SharedPreferences│                                              │
│  │   (Local Storage)│                                              │
│  └──────────────────┘                                              │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Layer Breakdown

### UI Layer

Located in `lib/screens/` and `lib/widgets/`, the UI layer consists of:

**Screens** (StatefulWidgets)
- `ServerListScreen` — Main screen displaying saved servers with pull-to-refresh
- `DeviceListScreen` — Device browser for a selected server
- `QRScannerScreen` — Full-screen QR code scanner with manual entry fallback
- `StreamViewerScreen` — Full-screen stream viewer with connection stats

**Widgets** (Stateless/StatefulWidgets)
- `ServerCard` — Displays server info with status dot and device count
- `DeviceRow` — Individual device row in device list
- `MiniPlayer` — Persistent stream indicator at bottom of screens
- `ConnectionStatusDot` — Animated status indicator for servers

### State Management

Located in `lib/providers/`:

**ServerProvider**
- Extends `ChangeNotifier` for reactive state updates
- Manages all application state including:
  - Server list (CRUD operations)
  - Active stream state
  - Device cache per server
  - Per-server connection status overrides

### Services

Located in `lib/services/`:

**ApiService**
- Handles HTTP communication with media server
- Implements `fetchDevices()` and `pingServer()` methods
- Throws custom exceptions for different error types

**StreamService**
- Manages WebSocket connections for live streaming
- Handles connection lifecycle: connect → auth → receive → disconnect
- Provides `startStream()` and `stopStream()` methods

**StorageService**
- Persists server list using SharedPreferences
- Implements `loadServers()` and `saveServers()` methods

### Models

Located in `lib/models/`:

**Server**
- Represents a connected media server
- Includes connection status, devices list, last connected timestamp
- Implements `toJson()` and `fromJson()` for serialization

**Device**
- Represents a media device (camera or microphone)
- Includes device ID, name, and type (video/audio)

---

## Data Flow

### Server Addition Flow

```
┌─────────────┐
│ User Scans  │
│ QR Code     │
└──────┬──────┘
       │
       ▼
┌──────────────────────┐
│ QRScannerScreen      │
│ _handleQRResult()    │
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐
│ parseQRCode()        │
│ → QRParsedData       │
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐
│ ApiService           │
│ fetchDevices()       │
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐
│ Media Server API     │
│ GET /devices         │
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐
│ Server Created       │
│ addServer()          │
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐
│ StorageService       │
│ saveServers()        │
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐
│ ServerProvider       │
│ notifyListeners()    │
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐
│ UI Rebuilds          │
│ Server appears in    │
│ list                 │
└──────────────────────┘
```

### Device Fetch Flow

```
┌─────────────┐
│ User Taps   │
│ Server      │
└──────┬──────┘
       │
       ▼
┌──────────────────────┐
│ ServerListScreen     │
│ _onServerTap()       │
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐
│ DeviceListScreen     │
│ initState()          │
│ _refreshDevices()    │
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐
│ ServerProvider       │
│ refreshServerDevices()│
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐
│ ApiService           │
│ fetchDevices()       │
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐
│ Media Server API     │
│ GET /devices         │
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐
│ Provider caches      │
│ devices, updates     │
│ server status        │
│ notifyListeners()    │
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐
│ DeviceListScreen     │
│ rebuilds with        │
│ device list          │
└──────────────────────┘
```

---

## Stream Flow

### WebSocket Connection Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                      STREAM CONNECTION                           │
└─────────────────────────────────────────────────────────────────┘

┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  idle    │───▶│ connecting│───▶│ connected │───▶│ streaming│
└──────────┘    └──────────┘    └──────────┘    └──────────┘
     │                │                │                │
     │                │                │                │
     │                │                │                ▼
     │                │                │         ┌──────────┐
     │                │                │         │  binary  │
     │                │                │         │  frames  │
     │                │                │         │  (H.264/  │
     │                │                │         │   Opus)  │
     │                │                │         └──────────┘
     │                │                │
     │                │                ▼
     │                │         ┌──────────┐
     │                │         │  PSK     │
     │                │         │  auth    │
     │                │         └──────────┘
     │                │
     │                ▼
     │         ┌──────────┐
     │         │  error   │◀───────┐
     └─────────┴──────────┘        │
                                   │
                                   ▼
                          ┌──────────┐
                          │disconnected│
                          └──────────┘
```

### StreamService Implementation

```dart
// 1. Create broadcast controller
final controller = StreamController<List<int>>.broadcast();

// 2. Connect WebSocket
final channel = WebSocketChannel.connect(Uri.parse(url));

// 3. Send PSK for authentication
channel.sink.add(psk);

// 4. Listen for incoming frames
channel.stream.listen(
  (data) {
    if (data is List<int>) {
      controller.add(data);  // Forward binary data
    }
  },
  onError: (error) {
    controller.addError(error);
  },
  onDone: () {
    controller.close();
  }
);

// 5. Cleanup on stop
await channel.sink.close();
await controller.close();
```

### State Propagation

```
StreamService.startStream()
    ↓
onStateChanged(StreamConnectionState.connecting)
    ↓
ServerProvider.setStreamState()
    ↓
notifyListeners()
    ↓
StreamViewerScreen rebuilds
    ↓
Shows connecting/loading state
```

---

## Navigation Flow

### Primary Navigation Paths

```
┌─────────────────────────────────────────────────────────────────┐
│                    SERVER LIST (Home)                           │
├─────────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────┐    │
│  │  [Server 1]  [Server 2]  [Server 3]                   │    │
│  └────────────────────────────────────────────────────────┘    │
│                         │                                       │
│        ┌────────────────┼────────────────┐                     │
│        │                │                │                     │
│        ▼                ▼                ▼                     │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐              │
│  │ Device List │ │ Device List │ │ Device List │              │
│  │   Screen    │ │   Screen    │ │   Screen    │              │
│  └──────┬──────┘ └──────┬──────┘ └──────┬──────┘              │
│         │               │               │                       │
│         └───────────────┴───────────────┘                       │
│                            │                                    │
│                            ▼                                    │
│                   ┌─────────────────┐                          │
│                   │ Stream Viewer   │                          │
│                   │    Screen       │                          │
│                   └────────┬────────┘                          │
│                            │                                   │
│                            ▼                                   │
│                   ┌─────────────────┐                          │
│                   │   Mini-Player   │                          │
│                   │ (Persistent)    │                          │
│                   └─────────────────┘                          │
└─────────────────────────────────────────────────────────────────┘
```

### Navigation Types

1. **Modal Push** — `Navigator.push()` for full-screen transitions
   - Server List → Device List
   - Device List → Stream Viewer
   - Server List → QR Scanner

2. **Modal Pop** — `Navigator.pop()` to return to previous screen
   - Stream Viewer → Device List
   - QR Scanner → Server List

3. **Persistent Widget** — `bottomSheet` for Mini-Player
   - Appears on all screens when stream is active
   - Does not block navigation

---

## State Management

### Why Provider/ChangeNotifier?

**Chosen Pattern:** Provider with ChangeNotifier

**Rationale:**

1. **Simplicity** — Minimal boilerplate for state updates
2. **Reactive** — Automatic UI rebuilds when state changes
3. **Testable** — Easy to mock and test in isolation
4. **Flutter-native** — Built into Flutter SDK, no external dependencies
5. **Unidirectional** — Clear data flow from providers to UI

### State Structure

```dart
class ServerProvider extends ChangeNotifier {
  // Server list state
  List<Server> _servers = [];
  
  // Active stream state
  Server? _activeStreamServer;
  Device? _activeStreamDevice;
  StreamConnectionState _streamState = StreamConnectionState.idle;
  StreamSession? _streamSession;
  int _bytesReceived = 0;
  
  // Cached data
  final Map<String, List<Device>> _deviceCache = {};
  
  // Ephemeral status overrides
  final Map<String, ServerStatus> _statusOverrides = {};
  
  // Getters for read-only access
  List<Server> get servers => List.unmodifiable(_servers);
  StreamConnectionState get streamState => _streamState;
  
  // Methods that mutate state and notify
  void addServer(Server server) {
    _servers.add(server);
    notifyListeners();
    _storage.saveServers(_servers);
  }
  
  void startStreaming(Server server, Device device) {
    _activeStreamServer = server;
    _activeStreamDevice = device;
    _streamState = StreamConnectionState.connecting;
    notifyListeners();
  }
}
```

### Provider Initialization

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final prefs = await SharedPreferences.getInstance();
  final storageService = StorageService(prefs);
  final apiService = ApiService();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ServerProvider(storageService, apiService)
            ..loadServers(),  // Initialize with persisted data
        ),
      ],
      child: const MediaStreamerApp(),
    )
  );
}
```

### Consumer Pattern

```dart
// In UI widgets
Consumer<ServerProvider>(
  builder: (context, provider, _) {
    final servers = provider.servers;
    final state = provider.streamState;
    
    return ListView.builder(
      itemCount: servers.length,
      itemBuilder: (context, index) {
        return ServerCard(
          server: servers[index],
          onTap: () => _navigateToDeviceList(servers[index]),
        );
      }
    );
  }
)
```

---

## Error Handling

### Custom Exceptions

Located in `ApiService`:

```dart
class ApiException implements Exception {
  final String message;
  final int? statusCode;
}

class InvalidPSKException extends ApiException {
  // HTTP 401 — authentication failed
}

class ConnectionTimeoutException extends ApiException {
  // Connection timed out
}

class NetworkException extends ApiException {
  // Network unreachable
}
```

### Error Handling Strategy

1. **Service Layer** — Throws custom exceptions for specific error types
2. **Provider Layer** — Catches exceptions, updates status, rethrows for propagation
3. **UI Layer** — Displays user-friendly error messages with retry options

### UI Error States

**Device List Screen:**
```dart
if (_errorMessage != null) {
  return _ErrorState(
    message: _errorMessage!,
    onRetry: _refreshDevices,
  );
}
```

**Stream Viewer Screen:**
```dart
case StreamConnectionState.error:
  return _ErrorState();  // Shows retry button
```

**QR Scanner Screen:**
```dart
if (_errorMessage != null) {
  return _buildErrorOverlay();  // Shows error with retry/close options
}
```

### Error Flow Example

```
User taps device
    ↓
ApiService.fetchDevices()
    ↓
Server returns 401
    ↓
InvalidPSKException thrown
    ↓
DeviceListScreen catches exception
    ↓
setState with error message
    ↓
ErrorState widget displays
    ↓
User taps retry → _refreshDevices() called
```

---

## Persistence

### Storage Mechanism

**Technology:** SharedPreferences (key-value storage)

**Key:** `saved_servers`

**Value:** JSON string array of serialized Server objects

### Server Serialization

```dart
// To JSON
Map<String, dynamic> toJson() => {
      'id': id,
      'name': name,
      'address': address,
      'psk': psk,
      'tlsFingerprint': tlsFingerprint,
      'isTls': isTls,
      'status': status.name,
      'devices': devices.map((d) => d.toJson()).toList(),
      'lastConnected': lastConnected?.toIso8601String(),
    };

// From JSON
factory Server.fromJson(Map<String, dynamic> json) => Server(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String,
      psk: json['psk'] as String,
      tlsFingerprint: json['tlsFingerprint'] as String?,
      isTls: json['isTls'] as bool? ?? false,
      status: ServerStatus.values.byName(
          json['status'] as String? ?? 'offline'),
      devices: (json['devices'] as List<dynamic>?)
              ?.map((d) => Device.fromJson(d as Map<String, dynamic>))
              .toList() ?? [],
      lastConnected: json['lastConnected'] != null
          ? DateTime.parse(json['lastConnected'] as String)
          : null,
    );
```

### Persistence Flow

```
App Start
    ↓
ServerProvider.loadServers()
    ↓
StorageService.loadServers()
    ↓
SharedPreferences.getString('saved_servers')
    ↓
JSON.parse() → List<Server>
    ↓
Provider state initialized
    ↓
notifyListeners() → UI rebuilds
```

```
User Adds Server
    ↓
ServerProvider.addServer()
    ↓
StorageService.saveServers()
    ↓
SharedPreferences.setString('saved_servers', json)
    ↓
Server persisted
```

### Data Scope

- **Persisted:** Server list (name, address, PSK, TLS fingerprint, device count)
- **Not Persisted:** Stream state, bytes received, ephemeral status overrides
- **Cached In-Memory:** Device list (refreshed on demand via API)

---

## Key Design Decisions

### 1. Provider Pattern Over Redux/Bloc

**Decision:** Use Provider/ChangeNotifier

**Trade-off:** Less structured than Redux/Bloc, but simpler for this app's state complexity. Provider provides sufficient reactivity without boilerplate.

### 2. WebSocket in Service Layer

**Decision:** StreamService manages WebSocket lifecycle separately from UI

**Trade-off:** Separation of concerns, but requires explicit state callbacks. Alternative: Handle WebSocket directly in UI with more code duplication.

### 3. Ephemeral Status Overrides

**Decision:** Store connection status in `_statusOverrides` Map, not persisted

**Trade-off:** Fast status updates without I/O, but status resets on app restart. Alternative: Persist status but adds complexity.

### 4. Device Cache Per Server

**Decision:** Cache device list in `_deviceCache` Map keyed by server ID

**Trade-off:** Reduces API calls, but cache may be stale. Alternative: Invalidate cache on every fetch (more API calls).

### 5. Broadcast Stream Controller

**Decision:** Use `StreamController.broadcast()` for stream data

**Trade-off:** Multiple listeners can subscribe without affecting each other. Alternative: Non-broadcast controller (simpler cleanup).

### 6. Dark-Only Theme

**Decision:** Force dark theme (`themeMode: ThemeMode.dark`)

**Trade-off:** Consistent dark UI, but no light theme option. Alternative: Support both themes with user preference.

### 7. Manual Entry Fallback

**Decision:** QR scanner offers manual entry dialog for PSK-only QR codes

**Trade-off:** More flexible, but adds extra steps for users. Alternative: Reject PSK-only QR codes.

### 8. Mini-Player Bottom Sheet

**Decision:** Use `bottomSheet` instead of persistent navigation state

**Trade-off:** Always visible without cluttering navigation stack. Alternative: Keep stream state in navigation but requires more complex UI.

---

## File Organization

```
lib/
├── main.dart              # App bootstrap, provider initialization
├── app.dart               # Root widget (MaterialApp)
│
├── models/
│   ├── server.dart        # Server data model
│   └── device.dart        # Device data model
│
├── providers/
│   └── server_provider.dart  # Central state management
│
├── screens/
│   ├── server_list_screen.dart   # Home screen
│   ├── device_list_screen.dart   # Device browser
│   ├── qr_scanner_screen.dart    # QR scanner
│   └── stream_viewer_screen.dart # Stream viewer
│
├── services/
│   ├── api_service.dart          # HTTP client
│   ├── stream_service.dart       # WebSocket manager
│   └── storage_service.dart      # Local persistence
│
├── widgets/
│   ├── server_card.dart          # Server list item
│   ├── device_row.dart           # Device list item
│   ├── mini_player.dart          # Active stream indicator
│   └── connection_status_dot.dart # Status indicator
│
├── theme/
│   └── app_theme.dart            # Material 3 dark theme
│
└── utils/
    └── qr_parser.dart            # QR code JSON parser
```
