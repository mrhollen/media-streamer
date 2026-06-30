import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_streamer_client/models/server.dart';
import 'package:media_streamer_client/models/device.dart';
import 'package:media_streamer_client/services/storage_service.dart';
import 'package:media_streamer_client/services/api_service.dart';
import 'package:media_streamer_client/services/stream_service.dart';

/// Central state management for servers, devices, and active streams.
///
/// Uses ChangeNotifier so the UI rebuilds when state changes.
class ServerProvider extends ChangeNotifier {
  final StorageService _storage;
  final ApiService _api;

  // -- Server list --
  List<Server> _servers = [];

  // -- Active stream --
  Server? _activeStreamServer;
  Device? _activeStreamDevice;
  StreamConnectionState _streamState = StreamConnectionState.idle;
  StreamSession? _streamSession;
  int _bytesReceived = 0;
  String? _streamError;

  // -- Per-server cached device lists --
  final Map<String, List<Device>> _deviceCache = {};

  // -- Per-server connection status overrides (ephemeral) --
  final Map<String, ServerStatus> _statusOverrides = {};

  // -----------------------------------------------------------------------
  // Constructor
  // -----------------------------------------------------------------------

  ServerProvider(this._storage, this._api) {
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] Constructor: ServerProvider initialised');
  }

  // -----------------------------------------------------------------------
  // Getters
  // -----------------------------------------------------------------------

  List<Server> get servers => List.unmodifiable(_servers);
  Server? get activeStreamServer => _activeStreamServer;
  Device? get activeStreamDevice => _activeStreamDevice;
  StreamConnectionState get streamState => _streamState;
  bool get hasActiveStream => _streamState == StreamConnectionState.streaming;
  int get bytesReceived => _bytesReceived;
  StreamSession? get streamSession => _streamSession;
  String? get streamError => _streamError;

  /// Get the cached device list for a server.
  List<Device> getDevices(String serverId) =>
      _deviceCache[serverId] ?? const [];

  /// Get the effective status for a server (override or persisted value).
  ServerStatus getServerStatus(String serverId) {
    final override = _statusOverrides[serverId];
    if (override != null) return override;
    final server = _servers.firstWhere(
      (s) => s.id == serverId,
      orElse: () => Server(
        id: serverId,
        name: '',
        address: '',
        psk: '',
        status: ServerStatus.offline,
      ),
    );
    return server.status;
  }

  // -----------------------------------------------------------------------
  // Server CRUD
  // -----------------------------------------------------------------------

  /// Load saved servers from persistent storage.
  Future<void> loadServers() async {
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] loadServers: loading from storage');
    _servers = await _storage.loadServers();
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] loadServers: loaded ${_servers.length} servers');
    notifyListeners();
  }

  /// Add a new server to the saved list and persist.
  void addServer(Server server) {
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] addServer: id="${server.id}" name="${server.name}" address="${server.address}"');
    _servers = List.from(_servers)..add(server);
    notifyListeners();
    _storage.saveServers(_servers);
  }

  /// Remove a server by id and persist.
  void removeServer(String id) {
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] removeServer: id="$id"');
    _servers = _servers.where((s) => s.id != id).toList();
    _deviceCache.remove(id);
    _statusOverrides.remove(id);
    notifyListeners();
    _storage.saveServers(_servers);
  }

  /// Rename a server by id and persist.
  void renameServer(String id, String newName) {
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] renameServer: id="$id" newName="$newName"');
    final index = _servers.indexWhere((s) => s.id == id);
    if (index != -1) {
      _servers[index] = _servers[index].copyWith(name: newName);
      notifyListeners();
      _storage.saveServers(_servers);
    }
  }

  // -----------------------------------------------------------------------
  // Device management
  // -----------------------------------------------------------------------

  /// Fetch devices from the server API and cache them.
  Future<void> refreshServerDevices(String serverId) async {
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] refreshServerDevices: serverId="$serverId"');
    final server = _servers.firstWhere((s) => s.id == serverId);
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] refreshServerDevices: server="${server.name}" address="${server.address}"');

    debugPrint('[${DateTime.now().toString()}] [ServerProvider] refreshServerDevices: setting status -> connecting');
    updateServerStatus(serverId, ServerStatus.connecting);

    try {
      debugPrint('[${DateTime.now().toString()}] [ServerProvider] refreshServerDevices: calling _api.fetchDevices(...)');
      final devices = await _api.fetchDevices(
        server.address,
        server.psk,
        isTls: server.isTls,
      );
      debugPrint('[${DateTime.now().toString()}] [ServerProvider] refreshServerDevices: received ${devices.length} devices from API');

      _deviceCache[serverId] = devices;
      // Also update the server's own device list for persistence
      final idx = _servers.indexWhere((s) => s.id == serverId);
      if (idx != -1) {
        _servers[idx] = server.copyWith(devices: devices);
      }
      debugPrint('[${DateTime.now().toString()}] [ServerProvider] refreshServerDevices: setting status -> connected');
      updateServerStatus(serverId, ServerStatus.connected);
      notifyListeners();
    } catch (e, st) {
      debugPrint('[${DateTime.now().toString()}] [ServerProvider] refreshServerDevices: EXCEPTION — $e');
      debugPrint('[${DateTime.now().toString()}] [ServerProvider] refreshServerDevices: stackTrace:\n$st');
      debugPrint('[${DateTime.now().toString()}] [ServerProvider] refreshServerDevices: setting status -> offline');
      updateServerStatus(serverId, ServerStatus.offline);
      notifyListeners();
      rethrow;
    }
  }

  /// Ping a server to check if it's reachable.
  Future<bool> pingServer(String serverId) async {
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] pingServer: serverId="$serverId"');
    final server = _servers.firstWhere((s) => s.id == serverId);
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] pingServer: server="${server.name}" address="${server.address}"');
    try {
      debugPrint('[${DateTime.now().toString()}] [ServerProvider] pingServer: calling _api.pingServer(...) with 8s timeout');
      final reachable = await _api.pingServer(
        server.address,
        server.psk,
        isTls: server.isTls,
      ).timeout(Duration(seconds: 8));
      debugPrint('[${DateTime.now().toString()}] [ServerProvider] pingServer: result=$reachable');
      updateServerStatus(
        serverId,
        reachable ? ServerStatus.connected : ServerStatus.offline,
      );
      return reachable;
    } on TimeoutException catch (e) {
      debugPrint('[${DateTime.now().toString()}] [ServerProvider] pingServer: TimeoutException — $e');
      updateServerStatus(serverId, ServerStatus.offline);
      return false;
    } catch (e, st) {
      debugPrint('[${DateTime.now().toString()}] [ServerProvider] pingServer: EXCEPTION — $e');
      debugPrint('[${DateTime.now().toString()}] [ServerProvider] pingServer: stackTrace:\n$st');
      updateServerStatus(serverId, ServerStatus.offline);
      return false;
    }
  }

  // -----------------------------------------------------------------------
  // Server status
  // -----------------------------------------------------------------------

  /// Update the ephemeral connection status of a server.
  void updateServerStatus(String id, ServerStatus status) {
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] updateServerStatus: id="$id" status=$status');
    _statusOverrides[id] = status;
    notifyListeners();
  }

  /// Clear all ephemeral status overrides (e.g., after a full refresh).
  void clearStatusOverrides() {
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] clearStatusOverrides: clearing ${_statusOverrides.length} overrides');
    _statusOverrides.clear();
    notifyListeners();
  }

  // -----------------------------------------------------------------------
  // Streaming
  // -----------------------------------------------------------------------

  /// Start streaming a device from a server.
  ///
  /// This sets the active stream state and notifies listeners. The actual
  /// WebSocket connection should be managed by the UI layer using
  /// [StreamService], calling [onStreamData] and [onStreamError] as events
  /// occur.
  void startStreaming(Server server, Device device) async {
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] startStreaming: server="${server.name}" (${server.address}) device="${device.name}" (${device.id})');

    // Clean up any existing session before starting a new one
    if (_streamSession != null) {
      debugPrint('[${DateTime.now().toString()}] [ServerProvider] startStreaming: existing session found, stopping first');
      final service = StreamService();
      await service.stopStream(_streamSession!);
      _streamSession = null;
      debugPrint('[${DateTime.now().toString()}] [ServerProvider] startStreaming: existing session stopped');
    } else {
      debugPrint('[${DateTime.now().toString()}] [ServerProvider] startStreaming: no existing session');
    }

    _activeStreamServer = server;
    _activeStreamDevice = device;
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] startStreaming: state change -> connecting, bytesReceived=0, error=null');
    _streamState = StreamConnectionState.connecting;
    _bytesReceived = 0;
    _streamError = null;
    notifyListeners();
  }

  /// Set the stream session associated with the active stream.
  void setStreamSession(StreamSession session) {
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] setStreamSession: session assigned (controllerIsClosed=${session.controller.isClosed})');
    _streamSession = session;
  }

  /// Called by the stream listener when binary data arrives.
  void onStreamData(List<int> data) {
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] onStreamData: received ${data.length} bytes (total before=$_bytesReceived)');
    _bytesReceived += data.length;
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] onStreamData: total bytesReceived=$_bytesReceived');
    // Only transition to streaming if not in an error or disconnected state
    if (_streamState != StreamConnectionState.error &&
        _streamState != StreamConnectionState.disconnected) {
      final oldState = _streamState;
      _streamState = StreamConnectionState.streaming;
      debugPrint('[${DateTime.now().toString()}] [ServerProvider] onStreamData: state transition $oldState -> streaming');
    } else {
      debugPrint('[${DateTime.now().toString()}] [ServerProvider] onStreamData: NOT transitioning state (current=$_streamState)');
    }
    notifyListeners();
  }

  /// Called when a stream error occurs.
  void onStreamError(String error) {
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] onStreamError: "$error"');
    _streamError = error;
    final oldState = _streamState;
    _streamState = StreamConnectionState.error;
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] onStreamError: state transition $oldState -> error');
    notifyListeners();
  }

  /// Disconnect from the current stream and reset state.
  Future<void> stopStreaming() async {
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] stopStreaming: starting (hasSession=${_streamSession != null})');
    if (_streamSession != null) {
      debugPrint('[${DateTime.now().toString()}] [ServerProvider] stopStreaming: disposing active session');
      final service = StreamService();
      await service.stopStream(_streamSession!);
      _streamSession = null;
    }

    _activeStreamServer = null;
    _activeStreamDevice = null;
    final oldState = _streamState;
    _streamState = StreamConnectionState.disconnected;
    _bytesReceived = 0;
    _streamError = null;
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] stopStreaming: state transition $oldState -> disconnected, bytesReset=0, errorReset=null');
    notifyListeners();
  }

  /// Update the stream connection state directly (called by the UI layer
  /// when StreamService emits state changes).
  void setStreamState(StreamConnectionState state) {
    final oldState = _streamState;
    _streamState = state;
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] setStreamState: $oldState -> $state');
    notifyListeners();
  }

  /// Reset the stream state to idle, clearing any error.
  /// Use this before retrying a connection to get a clean slate.
  void resetStreamState() {
    final oldState = _streamState;
    _streamState = StreamConnectionState.idle;
    _streamError = null;
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] resetStreamState: $oldState -> idle, error cleared');
    notifyListeners();
  }

  // -----------------------------------------------------------------------
  // Lifecycle
  // -----------------------------------------------------------------------

  @override
  Future<void> dispose() async {
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] dispose: starting cleanup');
    await stopStreaming();
    super.dispose();
    debugPrint('[${DateTime.now().toString()}] [ServerProvider] dispose: cleanup completed');
  }
}
