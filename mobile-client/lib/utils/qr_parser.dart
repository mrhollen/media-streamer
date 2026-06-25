import 'dart:convert';

/// Parsed result from a QR code scan.
class QRParsedData {
  final String psk;
  final String? host;
  final int? port;
  final String? tlsFingerprint;

  QRParsedData({
    required this.psk,
    this.host,
    this.port,
    this.tlsFingerprint,
  });

  /// Constructed address string (e.g. "192.168.1.5:8080").
  String get address {
    if (host != null) {
      final p = port ?? (isTls ? 443 : 8080);
      return '$host:$p';
    }
    return '';
  }

  bool get isTls => tlsFingerprint != null;
}

/// Parses a QR code payload into structured data.
///
/// Supports two formats:
/// - JSON: `{"psk": "...", "host": "...", "port": ..., "tls_sha256": "..."}`
/// - Plain text: just the PSK string
QRParsedData? parseQRCode(String data) {
  data = data.trim();

  // Try JSON first
  try {
    final json = jsonDecode(data) as Map<String, dynamic>;
    final psk = json['psk'] as String?;
    if (psk == null) return null;

    return QRParsedData(
      psk: psk,
      host: json['host'] as String?,
      port: json['port'] != null ? (json['port'] as num).toInt() : null,
      tlsFingerprint: json['tls_sha256'] as String?,
    );
  } catch (_) {
    // Not JSON, treat as plain PSK
    if (data.isNotEmpty) {
      return QRParsedData(psk: data);
    }
  }

  return null;
}
