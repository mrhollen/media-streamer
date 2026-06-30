import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:media_streamer_client/models/server.dart';
import 'package:media_streamer_client/models/device.dart';
import 'package:media_streamer_client/providers/server_provider.dart';
import 'package:media_streamer_client/services/stream_service.dart';

/// Full-screen immersive stream viewer for a single device.
///
/// Displays a visual "stream is active" indicator with connection stats.
/// Actual video/audio decoding is a future enhancement.
class StreamViewerScreen extends StatefulWidget {
  final Server server;
  final Device device;

  const StreamViewerScreen({
    super.key,
    required this.server,
    required this.device,
  });

  @override
  State<StreamViewerScreen> createState() => _StreamViewerScreenState();
}

class _StreamViewerScreenState extends State<StreamViewerScreen>
    with SingleTickerProviderStateMixin {
  // -- Stream stats --
  int _frameCount = 0;
  Duration _duration = Duration.zero;
  Timer? _timer;

  // -- Data subscription --
  StreamSubscription<List<int>>? _dataSubscription;

  // -- Animation --
  late final AnimationController _animationController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    debugPrint('[${DateTime.now().toString()}] [StreamViewer] initState: server="${widget.server.name}" (${widget.server.address}), device="${widget.device.name}" (${widget.device.id})');

    // Setup pulsing animation
    debugPrint('[${DateTime.now().toString()}] [StreamViewer] initState: creating AnimationController');
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.4, end: 0.8).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // Actually start the WebSocket stream connection
    debugPrint('[${DateTime.now().toString()}] [StreamViewer] initState: calling _startStreamConnection()');
    _startStreamConnection();

    // NOTE: _subscribeToStreamData() is now called inside _startStreamConnection()
    // after the session is created, to avoid a race condition.

    // Start duration timer
    debugPrint('[${DateTime.now().toString()}] [StreamViewer] initState: creating periodic timer (1s interval)');
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      debugPrint('[${DateTime.now().toString()}] [StreamViewer] timer tick: mounted=$mounted');
      if (mounted) {
        final provider = context.read<ServerProvider>();
        debugPrint('[${DateTime.now().toString()}] [StreamViewer] timer tick: provider.streamState=${provider.streamState}');
        if (provider.streamState == StreamConnectionState.streaming ||
            provider.streamState == StreamConnectionState.connected) {
          setState(() {
            _duration += const Duration(seconds: 1);
            debugPrint('[${DateTime.now().toString()}] [StreamViewer] timer tick: duration incremented to ${_duration.inSeconds}s');
          });
        } else {
          debugPrint('[${DateTime.now().toString()}] [StreamViewer] timer tick: skipping duration increment (state is ${provider.streamState})');
        }
      } else {
        debugPrint('[${DateTime.now().toString()}] [StreamViewer] timer tick: not mounted, skipping');
      }
    });
  }

  /// Actually initiate the WebSocket stream connection.
  Future<void> _startStreamConnection() async {
    debugPrint('[${DateTime.now().toString()}] [StreamViewer] _startStreamConnection: ENTERING method');
    final provider = context.read<ServerProvider>();
    final server = widget.server;
    final device = widget.device;

    debugPrint('[${DateTime.now().toString()}] [StreamViewer] _startStreamConnection: server.address="${server.address}" device.id="${device.id}" isTls=${server.isTls}');
    debugPrint('[${DateTime.now().toString()}] [StreamViewer] _startStreamConnection: provider.streamState BEFORE startStream = ${provider.streamState}');

    try {
      debugPrint('[${DateTime.now().toString()}] [StreamViewer] _startStreamConnection: creating StreamService instance');
      final service = StreamService();
      debugPrint('[${DateTime.now().toString()}] [StreamViewer] _startStreamConnection: calling service.startStream(...)');
      final session = await service.startStream(
        server.address,
        device.id,
        server.psk,
        isTls: server.isTls,
        onStateChanged: (state) {
          debugPrint('[${DateTime.now().toString()}] [StreamViewer] _startStreamConnection: onStateChanged callback fired -> $state, mounted=$mounted');
          if (mounted) {
            debugPrint('[${DateTime.now().toString()}] [StreamViewer] _startStreamConnection: calling provider.setStreamState($state)');
            provider.setStreamState(state);
          } else {
            debugPrint('[${DateTime.now().toString()}] [StreamViewer] _startStreamConnection: NOT calling provider.setStreamState — widget not mounted');
          }
        },
      );
      debugPrint('[${DateTime.now().toString()}] [StreamViewer] _startStreamConnection: service.startStream returned, session acquired');
      debugPrint('[${DateTime.now().toString()}] [StreamViewer] _startStreamConnection: calling provider.setStreamSession(session)');
      provider.setStreamSession(session);

      // Subscribe to stream data AFTER session is created
      debugPrint('[${DateTime.now().toString()}] [StreamViewer] _startStreamConnection: subscribing to session.controller.stream');
      _dataSubscription = session.controller.stream.listen(
        (data) {
          debugPrint('[${DateTime.now().toString()}] [StreamViewer] _dataSubscription: data received, bytes=${data.length}');
          provider.onStreamData(data);
          if (mounted) {
            setState(() {
              _frameCount++;
              debugPrint('[${DateTime.now().toString()}] [StreamViewer] _dataSubscription: frameCount incremented to $_frameCount');
            });
          }
        },
        onError: (error) {
          debugPrint('[${DateTime.now().toString()}] [StreamViewer] _dataSubscription: onError — $error');
          provider.onStreamError(error.toString());
        },
        onDone: () {
          debugPrint('[${DateTime.now().toString()}] [StreamViewer] _dataSubscription: onDone — stream completed');
          provider.setStreamState(StreamConnectionState.disconnected);
        },
      );
      debugPrint('[${DateTime.now().toString()}] [StreamViewer] _startStreamConnection: subscription set up successfully');
    } catch (e, st) {
      debugPrint('[${DateTime.now().toString()}] [StreamViewer] _startStreamConnection: EXCEPTION — $e');
      debugPrint('[${DateTime.now().toString()}] [StreamViewer] _startStreamConnection: stackTrace:\n$st');
      if (mounted) {
        debugPrint('[${DateTime.now().toString()}] [StreamViewer] _startStreamConnection: calling provider.onStreamError (mounted)');
        provider.onStreamError(e.toString());
      } else {
        debugPrint('[${DateTime.now().toString()}] [StreamViewer] _startStreamConnection: NOT calling provider.onStreamError — widget not mounted');
      }
    }
  }

  @override
  void dispose() {
    debugPrint('[${DateTime.now().toString()}] [StreamViewer] dispose: starting cleanup');
    // Unsubscribe from data listener only — do NOT stop the stream
    debugPrint('[${DateTime.now().toString()}] [StreamViewer] dispose: cancelling _dataSubscription');
    _dataSubscription?.cancel();
    debugPrint('[${DateTime.now().toString()}] [StreamViewer] dispose: cancelling _timer');
    _timer?.cancel();
    debugPrint('[${DateTime.now().toString()}] [StreamViewer] dispose: disposing _animationController');
    _animationController.dispose();
    super.dispose();
    debugPrint('[${DateTime.now().toString()}] [StreamViewer] dispose: cleanup completed');
  }

  // -----------------------------------------------------------------------
  // Build
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    debugPrint('[${DateTime.now().toString()}] [StreamViewer] build: called');
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer<ServerProvider>(
        builder: (context, provider, _) {
          final state = provider.streamState;
          debugPrint('[${DateTime.now().toString()}] [StreamViewer] build: Consumer builder — streamState=$state');

          return Stack(
            children: [
              // Center content based on state
              _buildCenterContent(state, provider),

              // Top overlay
              _buildTopOverlay(context, provider),

              // Bottom overlay
              _buildBottomOverlay(context),
            ],
          );
        },
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Center content (state-dependent)
  // -----------------------------------------------------------------------

  Widget _buildCenterContent(StreamConnectionState state, ServerProvider provider) {
    debugPrint('[${DateTime.now().toString()}] [StreamViewer] _buildCenterContent: state=$state');
    switch (state) {
      case StreamConnectionState.connecting:
      case StreamConnectionState.connected:
        debugPrint('[${DateTime.now().toString()}] [StreamViewer] _buildCenterContent: returning _ConnectingState');
        return const _ConnectingState();
      case StreamConnectionState.streaming:
        debugPrint('[${DateTime.now().toString()}] [StreamViewer] _buildCenterContent: returning _StreamingState');
        return _StreamingState(
          device: widget.device,
          animationController: _animationController,
          scaleAnimation: _scaleAnimation,
          opacityAnimation: _opacityAnimation,
        );
      case StreamConnectionState.error:
        debugPrint('[${DateTime.now().toString()}] [StreamViewer] _buildCenterContent: returning _ErrorState (error="${provider.streamError}")');
        return _ErrorState(errorMessage: provider.streamError);
      case StreamConnectionState.disconnected:
        debugPrint('[${DateTime.now().toString()}] [StreamViewer] _buildCenterContent: returning _DisconnectedState');
        return const _DisconnectedState();
      case StreamConnectionState.idle:
        debugPrint('[${DateTime.now().toString()}] [StreamViewer] _buildCenterContent: returning _IdleState');
        return const _IdleState();
    }
  }

  // -----------------------------------------------------------------------
  // Top overlay
  // -----------------------------------------------------------------------

  Widget _buildTopOverlay(BuildContext context, ServerProvider provider) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.8),
              Colors.transparent,
            ],
            stops: const [0.0, 0.6],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Back button
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    debugPrint('[${DateTime.now().toString()}] [StreamViewer] back button pressed: navigating away with Navigator.pop()');
                    Navigator.of(context).pop();
                  },
                ),

                // Device name and server name
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.device.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.server.name,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Connection status indicator
                _ConnectionStatusIndicator(
                  state: provider.streamState,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Bottom overlay
  // -----------------------------------------------------------------------

  Widget _buildBottomOverlay(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.8),
              Colors.transparent,
            ],
            stops: const [0.0, 0.6],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                // Stream stats
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatDuration(_duration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Frames: $_frameCount',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),

                // Fullscreen toggle icon
                IconButton(
                  icon: const Icon(
                    Icons.fullscreen_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    // Fullscreen toggle is a future enhancement
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

// =========================================================================
// State widgets
// =========================================================================

/// Spinning loader shown while the stream connection is being established.
class _ConnectingState extends StatelessWidget {
  const _ConnectingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
            ),
          ),
          SizedBox(height: 24),
          Text(
            'Connecting to stream...',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

/// Idle state shown before streaming has been initiated.
class _IdleState extends StatelessWidget {
  const _IdleState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.play_circle_outline_rounded,
            size: 64,
            color: Colors.white38,
          ),
          SizedBox(height: 16),
          Text(
            'Tap to start streaming',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

/// Animated visual indicator shown while the stream is active.
class _StreamingState extends StatelessWidget {
  final Device device;
  final AnimationController animationController;
  final Animation<double> scaleAnimation;
  final Animation<double> opacityAnimation;

  const _StreamingState({
    required this.device,
    required this.animationController,
    required this.scaleAnimation,
    required this.opacityAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final isVideo = device.type == DeviceType.video;

    return Center(
      child: AnimatedBuilder(
        animation: animationController,
        builder: (context, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulsing concentric circles
              _buildPulsingCircles(isVideo),

              const SizedBox(height: 32),

              // Label
              Text(
                isVideo ? 'Streaming...' : 'Listening...',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPulsingCircles(bool isVideo) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer ring
        AnimatedContainer(
          duration: const Duration(milliseconds: 750),
          width: 140 * scaleAnimation.value,
          height: 140 * scaleAnimation.value,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1 * opacityAnimation.value),
              width: 2,
            ),
          ),
        ),

        // Middle ring
        AnimatedContainer(
          duration: const Duration(milliseconds: 750),
          width: 100 * scaleAnimation.value,
          height: 100 * scaleAnimation.value,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2 * opacityAnimation.value),
              width: 2,
            ),
          ),
        ),

        // Inner filled circle
        AnimatedContainer(
          duration: const Duration(milliseconds: 750),
          width: 64 * scaleAnimation.value,
          height: 64 * scaleAnimation.value,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.08 * opacityAnimation.value),
          ),
        ),

        // Device type icon in center
        Icon(
          isVideo ? Icons.videocam_rounded : Icons.volume_up_rounded,
          size: 36,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      ],
    );
  }
}

/// Error state shown when the stream connection fails.
class _ErrorState extends StatelessWidget {
  final String? errorMessage;

  const _ErrorState({this.errorMessage});

  void _onRetry(BuildContext context) async {
    debugPrint('[${DateTime.now().toString()}] [StreamViewer] _ErrorState._onRetry: retry button pressed');
    final provider = context.read<ServerProvider>();
    final server = provider.activeStreamServer;
    final device = provider.activeStreamDevice;
    debugPrint('[${DateTime.now().toString()}] [StreamViewer] _ErrorState._onRetry: server=${server?.name} device=${device?.name}');
    if (server == null || device == null) {
      debugPrint('[${DateTime.now().toString()}] [StreamViewer] _ErrorState._onRetry: server or device is null, aborting retry');
      return;
    }
    debugPrint('[${DateTime.now().toString()}] [StreamViewer] _ErrorState._onRetry: calling provider.stopStreaming()');
    await provider.stopStreaming();
    debugPrint('[${DateTime.now().toString()}] [StreamViewer] _ErrorState._onRetry: calling provider.startStreaming()');
    provider.startStreaming(server, device);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: Colors.white54,
            ),
            const SizedBox(height: 16),
            const Text(
              'Stream connection failed',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (errorMessage != null && errorMessage!.isNotEmpty) ...[
              Text(
                errorMessage!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],
            Text(
              'Check the server is online and try again',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _onRetry(context),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Disconnected state shown when the stream ends.
class _DisconnectedState extends StatelessWidget {
  const _DisconnectedState();

  void _onRetry(BuildContext context) async {
    debugPrint('[${DateTime.now().toString()}] [StreamViewer] _DisconnectedState._onRetry: retry button pressed');
    final provider = context.read<ServerProvider>();
    final server = provider.activeStreamServer;
    final device = provider.activeStreamDevice;
    debugPrint('[${DateTime.now().toString()}] [StreamViewer] _DisconnectedState._onRetry: server=${server?.name} device=${device?.name}');
    if (server == null || device == null) {
      debugPrint('[${DateTime.now().toString()}] [StreamViewer] _DisconnectedState._onRetry: server or device is null, aborting retry');
      return;
    }
    debugPrint('[${DateTime.now().toString()}] [StreamViewer] _DisconnectedState._onRetry: calling provider.stopStreaming()');
    await provider.stopStreaming();
    debugPrint('[${DateTime.now().toString()}] [StreamViewer] _DisconnectedState._onRetry: calling provider.startStreaming()');
    provider.startStreaming(server, device);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.stop_circle_rounded,
              size: 64,
              color: Colors.white38,
            ),
            const SizedBox(height: 16),
            const Text(
              'Stream ended',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: () => _onRetry(context),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    debugPrint('[${DateTime.now().toString()}] [StreamViewer] _DisconnectedState: back button pressed, navigating away');
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// Connection status indicator widget
// =========================================================================

/// Small dot + label showing the current stream connection state.
class _ConnectionStatusIndicator extends StatelessWidget {
  final StreamConnectionState state;

  const _ConnectionStatusIndicator({required this.state});

  Color _dotColor() {
    return switch (state) {
      StreamConnectionState.connecting ||
      StreamConnectionState.connected =>
        Colors.orange,
      StreamConnectionState.streaming => Colors.green,
      StreamConnectionState.error => Colors.red,
      StreamConnectionState.disconnected ||
      StreamConnectionState.idle =>
        Colors.grey,
    };
  }

  String _label() {
    return switch (state) {
      StreamConnectionState.connecting => 'Connecting',
      StreamConnectionState.connected => 'Connected',
      StreamConnectionState.streaming => 'Live',
      StreamConnectionState.error => 'Error',
      StreamConnectionState.disconnected => 'Ended',
      StreamConnectionState.idle => 'Idle',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: _dotColor(),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _label(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
