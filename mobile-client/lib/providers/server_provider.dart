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

  // -- Per-server cached device lists --
  final Map<String, List<Device>> _deviceCache = {};

  // -- Per-server connection status overrides (ephemeral) --
  final Map<String, ServerStatus> _statusOverrides = {};

  // -----------------------------------------------------------------------
  // Constructor
  // -----------------------------------------------------------------------

  ServerProvider(this._storage, this._api);

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
    _servers = await _storage.loadServers();
    notifyListeners();
  }

  /// Add a new server to the saved list and persist.
  void addServer(Server server) {
    _servers = List.from(_servers)..add(server);
    notifyListeners();
    _storage.saveServers(_servers);
  }

  /// Remove a server by id and persist.
  void removeServer(String id) {
    _servers = _servers.where((s) => s.id != id).toList();
    _deviceCache.remove(id);
    _statusOverrides.remove(id);
    notifyListeners();
    _storage.saveServers(_servers);
  }

  /// Rename a server by id and persist.
  void renameServer(String id, String newName) {
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
    final server = _servers.firstWhere((s) => s.id == serverId);

    updateServerStatus(serverId, ServerStatus.connecting);

    try {
      final devices = await _api.fetchDevices(
        server.address,
        server.psk,
        isTls: server.isTls,
      );

      _deviceCache[serverId] = devices;
      // Also update the server's own device list for persistence
      final idx = _servers.indexWhere((s) => s.id == serverId);
      if (idx != -1) {
        _servers[idx] = server.copyWith(devices: devices);
      }
      updateServerStatus(serverId, ServerStatus.connected);
      notifyListeners();
    } catch (e) {
      updateServerStatus(serverId, ServerStatus.offline);
      notifyListeners();
      rethrow;
    }
  }

  /// Ping a server to check if it's reachable.
  Future<bool> pingServer(String serverId) async {
    final server = _servers.firstWhere((s) => s.id == serverId);
    try {
      final reachable = await _api.pingServer(
        server.address,
        server.psk,
        isTls: server.isTls,
      );
      updateServerStatus(
        serverId,
        reachable ? ServerStatus.connected : ServerStatus.offline,
      );
      return reachable;
    } catch (_) {
      updateServerStatus(serverId, ServerStatus.offline);
      return false;
    }
  }

  // -----------------------------------------------------------------------
  // Server status
  // -----------------------------------------------------------------------

  /// Update the ephemeral connection status of a server.
  void updateServerStatus(String id, ServerStatus status) {
    _statusOverrides[id] = status;
    notifyListeners();
  }

  /// Clear all ephemeral status overrides (e.g., after a full refresh).
  void clearStatusOverrides() {
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
  void startStreaming(Server server, Device device) {
    _activeStreamServer = server;
    _activeStreamDevice = device;
    _streamState = StreamConnectionState.connecting;
    _bytesReceived = 0;
    notifyListeners();
  }

  /// Set the stream session associated with the active stream.
  void setStreamSession(StreamSession session) {
    _streamSession = session;
  }

  /// Called by the stream listener when binary data arrives.
  void onStreamData(List<int> data) {
    _bytesReceived += data.length;
    _streamState = StreamConnectionState.streaming;
    notifyListeners();
  }

  /// Called when a stream error occurs.
  void onStreamError(String error) {
    _streamState = StreamConnectionState.error;
    notifyListeners();
  }

  /// Disconnect from the current stream and reset state.
  Future<void> stopStreaming() async {
    if (_streamSession != null) {
      final service = StreamService();
      await service.stopStream(_streamSession!);
      _streamSession = null;
    }

    _activeStreamServer = null;
    _activeStreamDevice = null;
    _streamState = StreamConnectionState.disconnected;
    _bytesReceived = 0;
    notifyListeners();
  }

  /// Update the stream connection state directly (called by the UI layer
  /// when StreamService emits state changes).
  void setStreamState(StreamConnectionState state) {
    _streamState = state;
    notifyListeners();
  }

  // -----------------------------------------------------------------------
  // Lifecycle
  // -----------------------------------------------------------------------

  @override
  Future<void> dispose() async {
    await stopStreaming();
    super.dispose();
  }
}
