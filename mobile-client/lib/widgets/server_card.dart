import 'package:flutter/material.dart';
import 'package:media_streamer_client/models/server.dart';
import 'package:media_streamer_client/models/device.dart';
import 'package:media_streamer_client/widgets/connection_status_dot.dart';

/// Card widget displaying a server's summary info.
///
/// Shows server name, connection status dot, device count badge, and
/// icon hints for device types. Supports tap and long-press interactions.
class ServerCard extends StatelessWidget {
  final Server server;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const ServerCard({
    super.key,
    required this.server,
    required this.onTap,
    required this.onLongPress,
  });

  /// Determine whether the server has any video devices.
  bool get _hasVideoDevices =>
      server.devices.any((d) => d.type == DeviceType.video);

  /// Determine whether the server has any audio devices.
  bool get _hasAudioDevices =>
      server.devices.any((d) => d.type == DeviceType.audio);

  int get _deviceCount => server.devices.length;

  @override
  Widget build(BuildContext context) {
    final isOffline = server.status == ServerStatus.offline;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: isOffline ? null : onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Connection status dot
              ConnectionStatusDot(status: server.status),
              const SizedBox(width: 14),

              // Server name + device info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Server name
                    Text(
                      server.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: isOffline
                            ? theme.textTheme.bodyLarge?.color?.withValues(alpha: 0.5)
                            : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Device count + type hints
                    Row(
                      children: [
                        // Device count badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$_deviceCount device${_deviceCount == 1 ? '' : 's'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isOffline
                                  ? theme.textTheme.bodySmall?.color
                                      ?.withValues(alpha: 0.5)
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (_hasVideoDevices) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.videocam_rounded,
                            size: 16,
                            color: isOffline
                                ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                        if (_hasAudioDevices) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.volume_up_rounded,
                            size: 16,
                            color: isOffline
                                ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Trailing chevron (or placeholder when offline)
              Icon(
                Icons.chevron_right_rounded,
                color: isOffline
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.2)
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
