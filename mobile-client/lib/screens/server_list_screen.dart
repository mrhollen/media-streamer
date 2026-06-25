import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:media_streamer_client/providers/server_provider.dart';
import 'package:media_streamer_client/models/server.dart';
import 'package:media_streamer_client/widgets/server_card.dart';
import 'package:media_streamer_client/widgets/mini_player.dart';
import 'device_list_screen.dart';
import 'qr_scanner_screen.dart';

/// Displays the list of saved media servers.
///
/// The root/home screen of the app. Supports pull-to-refresh,
/// long-press context menus (rename / remove), and a floating action
/// button to scan QR codes for new servers.
class ServerListScreen extends StatefulWidget {
  const ServerListScreen({super.key});

  @override
  State<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends State<ServerListScreen> {
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  /// Load servers from storage and ping all of them.
  Future<void> _initialize() async {
    final provider = context.read<ServerProvider>();
    await provider.loadServers();
    await _pingAllServers(provider);
  }

  /// Ping every saved server to update connection status.
  Future<void> _pingAllServers(ServerProvider provider) async {
    final servers = provider.servers;
    for (final server in servers) {
      provider.updateServerStatus(server.id, ServerStatus.connecting);
      await provider.pingServer(server.id);
    }
  }

  /// Pull-to-refresh handler: re-ping all servers.
  Future<void> _onRefresh() async {
    final provider = context.read<ServerProvider>();
    await _pingAllServers(provider);
  }

  /// Navigate to the device list for a server.
  void _onServerTap(Server server) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DeviceListScreen(server: server),
      ),
    );
  }

  /// Show QR scanner as a full-screen modal dialog.
  Future<void> _openQRScanner() async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'QR Scanner',
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const QRScannerScreen();
      },
    );
  }

  /// Show a context menu for a server card (rename / remove).
  void _showContextMenu(BuildContext context, Server server) {
    showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(16, 0, 16, 0),
      items: const [
        PopupMenuItem<String>(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit_rounded, size: 20),
              SizedBox(width: 12),
              Text('Rename'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'remove',
          child: Row(
            children: [
              Icon(Icons.delete_rounded, size: 20),
              SizedBox(width: 12),
              Text('Remove'),
            ],
          ),
        ),
      ],
    ).then((selected) {
      if (selected == null) return;

      if (selected == 'rename') {
        _showRenameDialog(server);
      } else if (selected == 'remove') {
        _showRemoveConfirmation(server);
      }
    });
  }

  /// Show a dialog to rename a server.
  Future<void> _showRenameDialog(Server server) async {
    final controller = TextEditingController(text: server.name);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename Server'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Server name',
            ),
            onSubmitted: (_) {
              Navigator.of(context).pop(true);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted && controller.text.trim().isNotEmpty) {
      context
          .read<ServerProvider>()
          .renameServer(server.id, controller.text.trim());
    }
  }

  /// Show a confirmation dialog before removing a server.
  Future<void> _showRemoveConfirmation(Server server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove Server'),
          content: Text(
            'Are you sure you want to remove "${server.name}"? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      context.read<ServerProvider>().removeServer(server.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Media Streamer'),
      ),
      body: Consumer<ServerProvider>(
        builder: (context, provider, _) {
          if (provider.servers.isEmpty) {
            return _buildEmptyState(context);
          }

          return RefreshIndicator(
            onRefresh: _onRefresh,
            child: ListView.builder(
              itemCount: provider.servers.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final server = provider.servers[index];
                return ServerCard(
                  server: server,
                  onTap: () => _onServerTap(server),
                  onLongPress: () => _showContextMenu(context, server),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openQRScanner,
        child: const Icon(Icons.qr_code_scanner),
      ),
      bottomSheet: const MiniPlayer(),
    );
  }

  /// Empty state shown when no servers have been added.
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cast_connected_rounded,
              size: 80,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 24),
            Text(
              'No servers yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Scan a QR code to connect to a media server',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _openQRScanner,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Add Server'),
            ),
          ],
        ),
      ),
    );
  }
}
