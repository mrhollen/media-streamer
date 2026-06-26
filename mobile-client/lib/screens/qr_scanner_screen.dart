import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:media_streamer_client/models/server.dart';
import 'package:media_streamer_client/providers/server_provider.dart';
import 'package:media_streamer_client/services/api_service.dart';
import 'package:media_streamer_client/utils/qr_parser.dart';
import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// QR Scanner Screen
// ---------------------------------------------------------------------------

/// Full-screen QR code scanner for quick server pairing.
///
/// Displays the camera preview with a scanner overlay, handles QR code
/// detection, parsing, server validation, and manual entry fallback.
class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController();
  final ApiService _api = ApiService();
  final _formKey = GlobalKey<FormState>();

  // -- Scanning state --
  bool _processing = false;
  bool _isFlashOn = false;

  // -- Connection overlay state --
  bool _showConnecting = false;
  bool _showSuccess = false;
  String? _errorMessage;

  // -- Manual entry fields --
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '8080');
  final _pskController = TextEditingController();
  bool _manualTls = false;
  String? _manualTlsFingerprint;

  // -- Viewfinder bounds (centered 240x240 area) --
  ui.Rect? _viewfinderBounds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    // Recalculate viewfinder bounds when screen size changes
    _updateViewfinderBounds();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _hostController.dispose();
    _portController.dispose();
    _pskController.dispose();
    super.dispose();
  }

  void _updateViewfinderBounds() {
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    final frameSize = 240.0;
    final x = (size.width - frameSize) / 2;
    final y = (size.height - frameSize) / 2 - 40;
    setState(() {
      _viewfinderBounds = ui.Rect.fromLTWH(x, y, frameSize, frameSize);
    });
  }

  // -----------------------------------------------------------------------
  // QR Detection
  // -----------------------------------------------------------------------

  void _onDetect(BarcodeCapture capture) {
    debugPrint('[QR-Connect] _onDetect called | _processing=$_processing');
    if (_processing) return;
    _processing = true;

    final barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final raw = barcodes.first.displayValue;
      if (raw != null && raw.isNotEmpty) {
        _handleQRResult(raw);
      } else {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _handleQRResult(String raw) async {
    // Pause the scanner while processing
    await _controller.stop();

    final parsed = parseQRCode(raw);
    debugPrint('[QR-Connect] _handleQRResult | raw length=${raw.length}, hasHost=${parsed?.host != null}, hasPort=${parsed?.port != null}');
    if (parsed == null) {
      setState(() {
        _processing = false;
        _errorMessage = 'Invalid QR code format';
      });
      return;
    }

    // If QR only contains a PSK, prompt for manual host/port
    if (parsed.host == null) {
      debugPrint('[QR-Connect] QR has no host, showing manual entry dialog');
      _showManualEntryDialog(
        psk: parsed.psk,
        host: parsed.host,
        port: parsed.port,
        isTls: parsed.isTls,
        tlsFingerprint: parsed.tlsFingerprint,
      );
      setState(() => _processing = false);
      await _controller.start();
      return;
    }

    debugPrint('[QR-Connect] QR has full data, connecting directly to ${parsed.host}:${parsed.port ?? 8080}');
    await _connectAndAddServer(
      host: parsed.host!,
      port: parsed.port ?? (parsed.isTls ? 443 : 8080),
      psk: parsed.psk,
      isTls: parsed.isTls,
      tlsFingerprint: parsed.tlsFingerprint,
    );
  }

  // -----------------------------------------------------------------------
  // Connection + Server Addition
  // -----------------------------------------------------------------------

  Future<void> _connectAndAddServer({
    required String host,
    required int port,
    required String psk,
    required bool isTls,
    String? tlsFingerprint,
  }) async {
    if (!mounted) return;

    debugPrint('[QR-Connect] _connectAndAddServer starting | host=$host, port=$port, isTls=$isTls, hasFingerprint=${tlsFingerprint != null}');

    setState(() {
      _showConnecting = true;
      _errorMessage = null;
      _showSuccess = false;
      _processing = true;  // Prevents QR detection from triggering new dialogs
    });

    final address = '$host:$port';
    final serverName = host;

    try {
      debugPrint('[QR-Connect] Fetching devices from $address...');
      // Fetch devices to validate the connection
      final devices = await _api.fetchDevices(
        address,
        psk,
        isTls: isTls,
      );

      debugPrint('[QR-Connect] Fetched ${devices.length} devices');

      final server = Server(
        id: const Uuid().v4(),
        name: serverName,
        address: address,
        psk: psk,
        tlsFingerprint: tlsFingerprint,
        isTls: isTls,
        status: ServerStatus.connected,
        devices: devices,
        lastConnected: DateTime.now(),
      );

      if (!mounted) return;

      debugPrint('[QR-Connect] Adding server to provider | mounted=$mounted');
      Provider.of<ServerProvider>(context, listen: false).addServer(server);
      debugPrint('[QR-Connect] Server added, showing success overlay');

      setState(() {
        _showConnecting = false;
        _showSuccess = true;
      });

      // Navigate back after a short delay
      await Future.delayed(const Duration(milliseconds: 1200));
      debugPrint('[QR-Connect] Success delay complete, attempting navigation | mounted=$mounted, canPop=${Navigator.of(context).canPop()}');
      try {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      } catch (_) {
        // Navigation failed, ignore
      }
    } on InvalidPSKException {
      debugPrint('[QR-Connect] Error: InvalidPSKException');
      if (mounted) {
        setState(() {
          _showConnecting = false;
          _errorMessage = 'Invalid credentials. Check your PSK.';
        });
      }
    } on ConnectionTimeoutException {
      debugPrint('[QR-Connect] Error: ConnectionTimeoutException');
      if (mounted) {
        setState(() {
          _showConnecting = false;
          _errorMessage = 'Server not reachable. Connection timed out.';
        });
      }
    } on NetworkException {
      debugPrint('[QR-Connect] Error: NetworkException');
      if (mounted) {
        setState(() {
          _showConnecting = false;
          _errorMessage = 'Server not reachable. Check network connection.';
        });
      }
    } on ApiException catch (e) {
      debugPrint('[QR-Connect] Error: ApiException -> ${e.message}');
      if (mounted) {
        setState(() {
          _showConnecting = false;
          _errorMessage = 'Connection failed: ${e.message}';
        });
      }
    } catch (e, stackTrace) {
      debugPrint('[QR-Connect] Error: Unexpected -> $e');
      debugPrint('[QR-Connect] Stack: $stackTrace');
      if (mounted) {
        setState(() {
          _showConnecting = false;
          _errorMessage = 'Unexpected error: $e';
        });
      }
    } finally {
      debugPrint('[QR-Connect] Finally block | mounted=$mounted');
      if (mounted) {
        setState(() {
          _showConnecting = false;
          _processing = false;
        });
      }
    }
  }

  Future<void> _retryConnection() async {
    setState(() {
      _errorMessage = null;
    });
    // Restart scanner to allow another scan
    try {
      await _controller.start();
    } catch (_) {}
  }

  // -----------------------------------------------------------------------
  // Manual Entry Dialog
  // -----------------------------------------------------------------------

  void _showManualEntryDialog({
    String? psk,
    String? host,
    int? port,
    bool? isTls,
    String? tlsFingerprint,
  }) {
    debugPrint('[QR-Connect] _showManualEntryDialog called | psk=${psk != null}, host=${host ?? "null"}, port=${port ?? "null"}, isTls=${isTls ?? false}, tlsFingerprint=${tlsFingerprint != null}');
    _manualTlsFingerprint = null;
    _pskController.text = psk ?? '';
    _hostController.text = host ?? '';
    _portController.text = port != null ? '$port' : '8080';
    _manualTls = isTls ?? false;
    _manualTlsFingerprint = tlsFingerprint;

    debugPrint('[QR-Connect] Controllers pre-filled | host="${_hostController.text}", port="${_portController.text}", psk="${_pskController.text.isNotEmpty ? "***" : ""}", tls=$_manualTls');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ManualEntryDialog(
        key: _formKey,
        hostController: _hostController,
        portController: _portController,
        pskController: _pskController,
        isTls: _manualTls,
        onTlsChanged: (v) => setState(() => _manualTls = v),
        onConnect: () async {
          debugPrint('[QR-Connect] onConnect callback triggered');
          final formState = _formKey.currentState;
          debugPrint('[QR-Connect] Form validation result: ${formState != null && formState.validate()}');
          if (formState == null || !formState.validate()) {
            debugPrint('[QR-Connect] Form validation FAILED, returning early');
            return;
          }

          Navigator.of(ctx).pop();
          debugPrint('[QR-Connect] Dialog popped, waiting 300ms for animation...');
          // Wait for dialog dismissal animation to complete before setState
          await Future.delayed(const Duration(milliseconds: 300));

          debugPrint('[QR-Connect] Delay complete | mounted=$mounted');
          if (!mounted) {
            debugPrint('[QR-Connect] Widget unmounted after delay, aborting connection');
            return;
          }

          await _connectAndAddServer(
            host: _hostController.text.trim(),
            port: int.tryParse(_portController.text.trim()) ?? 8080,
            psk: _pskController.text,
            isTls: _manualTls,
            tlsFingerprint: _manualTlsFingerprint,
          );
        },
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Flash Toggle
  // -----------------------------------------------------------------------

  Future<void> _toggleFlash() async {
    await _controller.toggleTorch();
    setState(() => _isFlashOn = !_isFlashOn);
  }

  // -----------------------------------------------------------------------
  // Close
  // -----------------------------------------------------------------------

  void _closeScanner() {
    Navigator.of(context).pop();
  }

  // -----------------------------------------------------------------------
  // Build
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    _updateViewfinderBounds();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            fit: BoxFit.cover,
            scanWindow: _viewfinderBounds,
          ),

          // Dark overlay with cutout
          _buildScannerOverlay(),

          // Top bar
          _buildTopBar(),

          // Bottom area
          _buildBottomArea(),

          // Flash toggle
          _buildFlashToggle(),

          // Connecting overlay
          if (_showConnecting) _buildConnectingOverlay(),

          // Success overlay
          if (_showSuccess) _buildSuccessOverlay(),

          // Error overlay
          if (_errorMessage != null) _buildErrorOverlay(),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Overlay with cutout
  // -----------------------------------------------------------------------

  Widget _buildScannerOverlay() {
    return CustomPaint(
      painter: _ScannerOverlayPainter(_viewfinderBounds),
      size: Size.infinite,
    );
  }

  // -----------------------------------------------------------------------
  // Top bar
  // -----------------------------------------------------------------------

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 8,
          left: 16,
          right: 16,
          bottom: 12,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Scan QR Code',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: _closeScanner,
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Flash toggle
  // -----------------------------------------------------------------------

  Widget _buildFlashToggle() {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 16,
      right: 72,
      child: GestureDetector(
        onTap: _toggleFlash,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _isFlashOn
                ? Colors.white.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _isFlashOn ? Icons.flash_on : Icons.flash_off,
            color: _isFlashOn ? Colors.yellow : Colors.white70,
            size: 24,
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Bottom area
  // -----------------------------------------------------------------------

  Widget _buildBottomArea() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: 16,
          left: 24,
          right: 24,
          bottom: MediaQuery.paddingOf(context).bottom + 24,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.8),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Point your camera at the server\'s QR code',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _showManualEntryDialog(),
              icon: const Icon(Icons.keyboard, size: 20),
              label: const Text('Enter Manually'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    Theme.of(context).colorScheme.secondaryContainer,
                foregroundColor:
                    Theme.of(context).colorScheme.onSecondaryContainer,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Connecting overlay
  // -----------------------------------------------------------------------

  Widget _buildConnectingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Connecting...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Success overlay
  // -----------------------------------------------------------------------

  Widget _buildSuccessOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 64),
            SizedBox(height: 12),
            Text(
              'Server Connected!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Error overlay
  // -----------------------------------------------------------------------

  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 56),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: _retryConnection,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white54),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    onPressed: _closeScanner,
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Manual Entry Dialog
// ---------------------------------------------------------------------------

/// Dialog for manually entering server connection details.
class _ManualEntryDialog extends StatefulWidget {
  final TextEditingController hostController;
  final TextEditingController portController;
  final TextEditingController pskController;
  final bool isTls;
  final ValueChanged<bool> onTlsChanged;
  final VoidCallback onConnect;

  const _ManualEntryDialog({
    super.key,
    required this.hostController,
    required this.portController,
    required this.pskController,
    required this.isTls,
    required this.onTlsChanged,
    required this.onConnect,
  });

  @override
  State<_ManualEntryDialog> createState() => _ManualEntryDialogState();
}

class _ManualEntryDialogState extends State<_ManualEntryDialog> {
  bool _connecting = false; // ignore: prefer_final_fields

  String? _validateHost(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Host is required';
    }
    return null;
  }

  String? _validatePort(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Port is required';
    }
    final port = int.tryParse(value.trim());
    if (port == null || port < 1 || port > 65535) {
      return 'Enter a valid port (1-65535)';
    }
    return null;
  }

  String? _validatePsk(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'PSK is required';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter Server Details'),
      content: Form(
        autovalidateMode: AutovalidateMode.disabled,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: widget.hostController,
                decoration: const InputDecoration(
                  labelText: 'Host',
                  hintText: '192.168.1.100',
                  prefixIcon: Icon(Icons.dns, size: 20),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.text,
                validator: _validateHost,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: widget.portController,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: '8080',
                  prefixIcon: Icon(Icons.speed, size: 20),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: _validatePort,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: widget.pskController,
                decoration: const InputDecoration(
                  labelText: 'PSK (Password)',
                  prefixIcon: Icon(Icons.lock, size: 20),
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                validator: _validatePsk,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    value: widget.isTls,
                    onChanged: (v) => widget.onTlsChanged(v ?? false),
                  ),
                  const Text('Use TLS'),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _connecting
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _connecting ? null : widget.onConnect,
          child: _connecting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Connect'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Scanner Overlay Painter
// ---------------------------------------------------------------------------

/// Paints a semi-transparent dark overlay with a rectangular cutout
/// and L-shaped corner brackets highlighting the scan area.
class _ScannerOverlayPainter extends CustomPainter {
  final ui.Rect? bounds;

  _ScannerOverlayPainter(this.bounds);

  @override
  void paint(Canvas canvas, Size size) {
    if (bounds == null) return;

    final overlayPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;

    // Draw dark overlay with a rectangular cutout
    final path = Path()
      ..addRect(ui.Offset.zero & size)
      ..addRect(bounds!)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, overlayPaint);

    // Draw corner brackets
    final cornerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final cornerLen = 28.0;
    final r = bounds!;

    // Top-left corner
    canvas.drawLine(
      Offset(r.left, r.top + cornerLen),
      Offset(r.left, r.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(r.left, r.top),
      Offset(r.left + cornerLen, r.top),
      cornerPaint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(r.right - cornerLen, r.top),
      Offset(r.right, r.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(r.right, r.top),
      Offset(r.right, r.top + cornerLen),
      cornerPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(r.left, r.bottom - cornerLen),
      Offset(r.left, r.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(r.left, r.bottom),
      Offset(r.left + cornerLen, r.bottom),
      cornerPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(r.right - cornerLen, r.bottom),
      Offset(r.right, r.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(r.right, r.bottom - cornerLen),
      Offset(r.right, r.bottom),
      cornerPaint,
    );

    // Draw subtle border around the scan area
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawRect(r, borderPaint);
  }

  @override
  bool shouldRepaint(_ScannerOverlayPainter oldDelegate) {
    return bounds != oldDelegate.bounds;
  }
}
