import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:media_streamer_client/models/server.dart';
import 'package:media_streamer_client/models/device.dart';
import 'package:media_streamer_client/providers/server_provider.dart';
import 'package:media_streamer_client/services/api_service.dart';
import 'stream_viewer_screen.dart';

/// Displays devices available on a selected server.
///
/// Navigated to from [ServerListScreen] with a [Server] argument.
/// Supports pull-to-refresh, loading/error/empty states, and
/// navigates to [StreamViewerScreen] on device tap.
class DeviceListScreen extends StatefulWidget {
  final Server server;

  const DeviceListScreen({super.key, required this.server});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _isLoading = true;
    _refreshDevices();
  }

  /// Fetch the device list for the current server.
  Future<void> _refreshDevices() async {
    final provider = context.read<ServerProvider>();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await provider.refreshServerDevices(widget.server.id);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load devices';
      });
    }
  }

  /// Pull-to-refresh handler.
  Future<void> _onRefresh() async {
    await _refreshDevices();
  }

  /// Start streaming and navigate to the stream viewer.
  void _onDeviceTap(Device device) {
    final provider = context.read<ServerProvider>();
    provider.startStreaming(widget.server, device);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StreamViewerScreen(
          server: widget.server,
          device: device,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.server.name),
      ),
      body: Consumer<ServerProvider>(
        builder: (context, provider, _) {
          final devices = provider.getDevices(widget.server.id);

          if (_isLoading) {
            return const _LoadingState();
          }

          if (_errorMessage != null) {
            return _ErrorState(
              message: _errorMessage!,
              onRetry: _refreshDevices,
            );
          }

          if (devices.isEmpty) {
            return const _EmptyState();
          }

          return RefreshIndicator(
            onRefresh: _onRefresh,
            child: ListView.separated(
              itemCount: devices.length,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final device = devices[index];
                return _DeviceCard(
                  device: device,
                  onTap: () => _onDeviceTap(device),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

/// Centered loading indicator.
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }
}

/// Error state with icon, message, and retry button.
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty state when no devices are found.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_off,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No devices found on this server',
              style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Card representing a single media device.
class _DeviceCard extends StatelessWidget {
  final Device device;
  final VoidCallback onTap;

  const _DeviceCard({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVideo = device.type == DeviceType.video;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Leading icon
              Icon(
                isVideo ? Icons.videocam : Icons.volume_up,
                size: 32,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 16),

              // Device name and type label
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isVideo ? 'Video Camera' : 'Audio Microphone',
                      style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                    ),
                  ],
                ),
              ),

              // Trailing play icon
              Icon(
                Icons.play_circle_outline_rounded,
                size: 32,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
