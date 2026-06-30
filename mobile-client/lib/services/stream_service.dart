import 'dart:async';
import 'package:flutter/foundation.dart';
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
    debugPrint('[${DateTime.now().toString()}] [StreamService] StreamHandle.dispose: cancelling subscription and closing channel');
    await subscription.cancel();
    await channel.sink.close();
    debugPrint('[${DateTime.now().toString()}] [StreamService] StreamHandle.dispose: completed');
  }
}

/// A stream controller paired with its internal WebSocket handle.
class StreamSession {
  final StreamController<List<int>> controller;
  StreamHandle? _handle;

  StreamSession(this.controller);

  void setHandle(StreamHandle handle) {
    debugPrint('[${DateTime.now().toString()}] [StreamService] StreamSession.setHandle: assigning handle');
    _handle = handle;
  }

  /// Dispose the underlying handle and close the stream controller.
  Future<void> dispose() async {
    debugPrint('[${DateTime.now().toString()}] [StreamService] StreamSession.dispose: starting (hasHandle=${_handle != null}, isControllerClosed=${controller.isClosed})');
    if (_handle != null) {
      await _handle!.dispose();
      _handle = null;
    }
    if (!controller.isClosed) {
      await controller.close();
    }
    debugPrint('[${DateTime.now().toString()}] [StreamService] StreamSession.dispose: completed');
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

  StreamService() {
    debugPrint('[${DateTime.now().toString()}] [StreamService] Constructor: StreamService initialised');
  }

  /// Build the WebSocket URL for a given server and device.
  static String buildStreamUrl(
    String address,
    String deviceId, {
    bool isTls = false,
  }) {
    final scheme = isTls ? 'wss' : 'ws';
    final clean = address.split('://').last;
    final url = '$scheme://$clean/stream/$deviceId';
    debugPrint('[${DateTime.now().toString()}] [StreamService] buildStreamUrl: address="$address" deviceId="$deviceId" isTls=$isTls => "$url"');
    return url;
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
    final url = buildStreamUrl(address, deviceId, isTls: isTls);
    debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: address="$address" deviceId="$deviceId" isTls=$isTls url="$url"');

    final controller = StreamController<List<int>>.broadcast();
    final session = StreamSession(controller);

    debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: notifying state change -> connecting');
    onStateChanged?.call(StreamConnectionState.connecting);

    try {
      // 1. Connect (returns channel synchronously, connection is async)
      debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: calling WebSocketChannel.connect("$url")');
      final channel = WebSocketChannel.connect(Uri.parse(url));
      debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: WebSocketChannel.connect returned, waiting for ready...');

      // 2. Wait for connection to establish, with timeout
      debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: awaiting channel.ready (timeout=${_connectionTimeout.inSeconds}s)');
      await channel.ready.timeout(
        _connectionTimeout,
        onTimeout: () {
          debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: connection TIMEOUT after ${_connectionTimeout.inSeconds}s, closing channel');
          channel.sink.close();
          throw Exception('Connection timed out after 10s');
        },
      );
      debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: channel.ready completed — WebSocket connection established');

      // 3. Send PSK
      debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: sending PSK auth message (${psk.length} chars)');
      channel.sink.add(psk);

      // 4. Track data reception and inactivity
      bool hasReceivedData = false;
      Timer? inactivityTimer;

      void startInactivityTimer() {
        debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: starting inactivity timer (${_inactivityTimeout.inSeconds}s)');
        inactivityTimer?.cancel();
        inactivityTimer = Timer(_inactivityTimeout, () {
          debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: INACTIVITY TIMEOUT — no data for ${_inactivityTimeout.inSeconds}s');
          if (!controller.isClosed) {
            onStateChanged?.call(StreamConnectionState.error);
            controller.addError(
              Exception('Stream inactive — no data received for 15s'),
            );
          }
        });
      }

      debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: setting up channel.stream.listen subscription');
      final subscription = channel.stream.listen(
        (data) {
          debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: onMessage received, type=${data.runtimeType}');
          if (data is List<int>) {
            debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: onMessage binary data received, bytes=${data.length}');
            hasReceivedData = true;
            debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: notifying state change -> streaming');
            onStateChanged?.call(StreamConnectionState.streaming);
            controller.add(data);
            startInactivityTimer();
          } else {
            debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: onMessage non-binary data, runtimeType=${data.runtimeType}, value=$data');
          }
        },
        onError: (error) {
          debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: onError — $error');
          onStateChanged?.call(StreamConnectionState.error);
          if (!controller.isClosed) {
            controller.addError(error);
          }
        },
        onDone: () {
          debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: onDone — stream closed by remote, hasReceivedData=$hasReceivedData');
          inactivityTimer?.cancel();
          if (!hasReceivedData) {
            debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: onDone -> notifying state change -> error (no data ever received)');
            onStateChanged?.call(StreamConnectionState.error);
          } else {
            debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: onDone -> notifying state change -> disconnected');
            onStateChanged?.call(StreamConnectionState.disconnected);
          }
        },
      );

      debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: setting handle on session');
      session.setHandle(StreamHandle(channel, subscription));
      startInactivityTimer();

      debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: notifying state change -> connected');
      onStateChanged?.call(StreamConnectionState.connected);
      debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: returning session successfully');
      return session;
    } catch (e, stackTrace) {
      debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: EXCEPTION caught — $e');
      debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: stackTrace:\n$stackTrace');
      debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: notifying state change -> error');
      onStateChanged?.call(StreamConnectionState.error);
      if (!controller.isClosed) {
        controller.addError(e);
      }
      await controller.close();
      debugPrint('[${DateTime.now().toString()}] [StreamService] startStream: returning session after error');
      return session;
    }
  }

  /// Stop an active stream and clean up resources.
  Future<void> stopStream(StreamSession session) async {
    debugPrint('[${DateTime.now().toString()}] [StreamService] stopStream: disposing session (controllerIsClosed=${session.controller.isClosed})');
    await session.dispose();
    debugPrint('[${DateTime.now().toString()}] [StreamService] stopStream: completed');
  }
}
