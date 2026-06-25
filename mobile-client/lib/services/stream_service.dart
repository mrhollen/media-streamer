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
      final channel = WebSocketChannel.connect(Uri.parse(url));

      // Send PSK as the first text frame for authentication
      channel.sink.add(psk);

      // Listen for incoming frames
      final subscription = channel.stream.listen(
        (data) {
          if (data is List<int>) {
            onStateChanged?.call(StreamConnectionState.streaming);
            controller.add(data);
          }
        },
        onError: (error) {
          onStateChanged?.call(StreamConnectionState.error);
          controller.addError(error);
        },
        onDone: () {
          onStateChanged?.call(StreamConnectionState.disconnected);
        },
      );

      // Store the handle on the session for cleanup
      session.setHandle(StreamHandle(channel, subscription));

      onStateChanged?.call(StreamConnectionState.connected);
      return session;
    } catch (e) {
      onStateChanged?.call(StreamConnectionState.error);
      await controller.close();
      rethrow;
    }
  }

  /// Stop an active stream and clean up resources.
  Future<void> stopStream(StreamSession session) async {
    await session.dispose();
  }
}
