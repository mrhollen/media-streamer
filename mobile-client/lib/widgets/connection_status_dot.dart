import 'package:flutter/material.dart';
import 'package:media_streamer_client/models/server.dart';

/// Small colored dot indicating server connection status.
///
/// Sizes: 8 px for compact contexts, 10 px by default.
/// Animates with a subtle pulse when in [ServerStatus.connecting].
class ConnectionStatusDot extends StatelessWidget {
  final ServerStatus status;
  final double size;

  const ConnectionStatusDot({
    super.key,
    required this.status,
    this.size = 10,
  });

  Color _resolveColor(BuildContext context) {
    return switch (status) {
      ServerStatus.connected => Colors.green,
      ServerStatus.connecting => Colors.orange,
      ServerStatus.offline => Colors.grey.shade500,
    };
  }

  @override
  Widget build(BuildContext context) {
    final dot = _buildDot(context);

    if (status == ServerStatus.connecting) {
      return _ConnectingPulse(size: size, child: dot);
    }

    return dot;
  }

  Widget _buildDot(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _resolveColor(context),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Wraps a child dot in a subtle pulsing animation to indicate
/// that a connection attempt is in progress.
class _ConnectingPulse extends StatefulWidget {
  final double size;
  final Widget child;

  const _ConnectingPulse({required this.size, required this.child});

  @override
  State<_ConnectingPulse> createState() => _ConnectingPulseState();
}

class _ConnectingPulseState extends State<_ConnectingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.6).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.5, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Pulsing ring behind the dot
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Opacity(
                opacity: _opacityAnimation.value,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: const BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          },
        ),
        // Solid dot on top
        widget.child,
      ],
    );
  }
}
