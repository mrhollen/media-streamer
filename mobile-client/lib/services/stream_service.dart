import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';

// ---------------------------------------------------------------------------
// Connection state
// ---------------------------------------------------------------------------

/// Represents the lifecycle state of a WebSocket stream connection.
enum StreamConnectionState {
  idle,       // No connection active
  connecting, // Attempting to open WebSocket
  connected,  // WebSocket open and authenticated
  streaming,  // Actively receiving binary frames
  error,      // Connection failed or lost
  disconnected, // Cleanly closed
}

// ---------------------------------------------------------------------------
// Internal handle wrapping a WebSocket channel + subscription
// ---------------------------------------------------------------------------

/// Lightweight wrapper holding the WebSocket channel and its subscription.
class StreamHandle {
  final WebSocketChannel channel;
  final StreamSubscription<dynamic> subscription;

  StreamHandle(this.channel, this.subscription);

  /// Cancel the subscription and close the channel sink.
  Future<void> dispose() async {
    await subscription.cancel();
    await channel.sink.close();
  }
}

/// A stream controller paired with its internal WebSocket handle.
class StreamSession {
  final StreamController<List<int>> controller;
  StreamHandle? _handle;

  StreamSession(this.controller);

  void setHandle(StreamHandle handle) => _handle = handle;

  /// Dispose the underlying handle and close the stream controller.
  Future<void> dispose() async {
    if (_handle != null) {
      await _handle!.dispose();
      _handle = null;
    }
    if (!controller.isClosed) {
      await controller.close();
    }
  }
}

// ---------------------------------------------------------------------------
// StreamService
// ---------------------------------------------------------------------------

/// Manages WebSocket connections for live media streams.
///
/// The server-side WebSocket protocol:
/// 1. Client connects to `ws://host:port/stream/{deviceId}` (or `wss://` for TLS).
/// 2. Client sends the PSK as the first text frame.
/// 3. Server validates PSK; if invalid, closes with status 403 (PolicyViolation).
/// 4. Subsequent frames from the server are binary (raw H.264 or Opus data).
class StreamService {
  static const Duration _connectionTimeout = Duration(seconds: 10);
  static const Duration _inactivityTimeout = Duration(seconds: 15);

  /// Build the WebSocket URL for a given server and device.
  static String buildStreamUrl(
    String address,
    String deviceId, {
    bool isTls = false,
  }) {
    final scheme = isTls ? 'wss' : 'ws';
    final clean = address.split('://').last;
    return '$scheme://$clean/stream/$deviceId';
  }

  /// Start a stream and return a [StreamSession] containing the controller.
  ///
  /// The caller is responsible for calling [stopStream] when done.
  ///
  /// [onStateChanged] is called whenever the connection state changes, allowing
  /// the caller to update UI accordingly.
  Future<StreamSession> startStream(
    String address,
    String deviceId,
    String psk, {
    bool isTls = false,
    void Function(StreamConnectionState)? onStateChanged,
  }) async {
    final controller = StreamController<List<int>>.broadcast();
    final session = StreamSession(controller);
    final url = buildStreamUrl(address, deviceId, isTls: isTls);

    onStateChanged?.call(StreamConnectionState.connecting);

    try {
      // 1. Connect (returns channel synchronously, connection is async)
      final channel = WebSocketChannel.connect(Uri.parse(url));

      // 2. Wait for connection to establish, with timeout
      await channel.ready.timeout(
        _connectionTimeout,
        onTimeout: () {
          channel.sink.close();
          throw Exception('Connection timed out after 10s');
        },
      );

      // 3. Send PSK
      channel.sink.add(psk);

      // 4. Track data reception and inactivity
      bool hasReceivedData = false;
      Timer? inactivityTimer;

      void startInactivityTimer() {
        inactivityTimer?.cancel();
        inactivityTimer = Timer(_inactivityTimeout, () {
          if (!controller.isClosed) {
            onStateChanged?.call(StreamConnectionState.error);
            controller.addError(
              Exception('Stream inactive — no data received for 15s'),
            );
          }
        });
      }

      final subscription = channel.stream.listen(
        (data) {
          if (data is List<int>) {
            hasReceivedData = true;
            onStateChanged?.call(StreamConnectionState.streaming);
            controller.add(data);
            startInactivityTimer();
          }
        },
        onError: (error) {
          onStateChanged?.call(StreamConnectionState.error);
          if (!controller.isClosed) {
            controller.addError(error);
          }
        },
        onDone: () {
          inactivityTimer?.cancel();
          if (!hasReceivedData) {
            onStateChanged?.call(StreamConnectionState.error);
          } else {
            onStateChanged?.call(StreamConnectionState.disconnected);
          }
        },
      );

      session.setHandle(StreamHandle(channel, subscription));
      startInactivityTimer();

      onStateChanged?.call(StreamConnectionState.connected);
      return session;
    } catch (e) {
      onStateChanged?.call(StreamConnectionState.error);
      if (!controller.isClosed) {
        controller.addError(e);
      }
      await controller.close();
      return session;
    }
  }

  /// Stop an active stream and clean up resources.
  Future<void> stopStream(StreamSession session) async {
    await session.dispose();
  }
}
