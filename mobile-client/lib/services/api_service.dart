import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io' show SocketException;
import 'package:http/http.dart' as http;
import 'package:media_streamer_client/models/device.dart';

// ---------------------------------------------------------------------------
// Custom exceptions
// ---------------------------------------------------------------------------

/// Base exception for API-related errors.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException({required this.message, this.statusCode});

  @override
  String toString() => 'ApiException[$statusCode]: $message';
}

/// Thrown when the server rejects the PSK (HTTP 401).
class InvalidPSKException extends ApiException {
  InvalidPSKException({super.message = 'Invalid PSK — authentication failed'})
      : super(statusCode: 401);
}

/// Thrown when the connection to the server times out.
class ConnectionTimeoutException extends ApiException {
  ConnectionTimeoutException({super.message = 'Connection timed out'})
      : super(statusCode: 0);
}

/// Thrown when the network is unreachable.
class NetworkException extends ApiException {
  NetworkException({super.message = 'Network unreachable'})
      : super(statusCode: 0);
}

// ---------------------------------------------------------------------------
// ApiService
// ---------------------------------------------------------------------------

/// Handles HTTP communication with the media streaming server.
class ApiService {
  static const _timeout = Duration(seconds: 10);

  /// Build the base URL for a server address.
  String _baseUrl(String address, {bool isTls = false}) {
    final scheme = isTls ? 'https' : 'http';
    // Ensure address doesn't already contain a scheme
    final clean = address.split('://').last;
    return '$scheme://$clean';
  }

  /// Common auth headers for every request.
  Map<String, String> _authHeaders(String psk) => {
        'Authorization': 'Bearer $psk',
        'Content-Type': 'application/json',
      };

  /// Fetch the list of devices available on a server.
  ///
  /// Calls `GET /devices` on the media streaming server.
  Future<List<Device>> fetchDevices(
    String address,
    String psk, {
    bool isTls = false,
  }) async {
    final url = Uri.parse('${_baseUrl(address, isTls: isTls)}/devices');

    try {
      final response = await http
          .get(url, headers: _authHeaders(psk))
          .timeout(_timeout);

      switch (response.statusCode) {
        case 200:
          return _parseDeviceList(response.body);

        case 401:
          throw InvalidPSKException();

        default:
          throw ApiException(
            message: 'Unexpected response: ${response.statusCode}',
            statusCode: response.statusCode,
          );
      }
    } on SocketException {
      throw NetworkException(message: 'Failed to connect to $address');
    } on TimeoutException {
      throw ConnectionTimeoutException(message: 'Connection to $address timed out');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to fetch devices: $e');
    }
  }

  /// Quick connectivity check against the server.
  ///
  /// Calls `GET /devices` and returns `true` if the server responds with 200.
  Future<bool> pingServer(
    String address,
    String psk, {
    bool isTls = false,
  }) async {
    final url = Uri.parse('${_baseUrl(address, isTls: isTls)}/devices');

    try {
      final response = await http
          .get(url, headers: _authHeaders(psk))
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // -----------------------------------------------------------------
  // Internal helpers
  // -----------------------------------------------------------------

  List<Device> _parseDeviceList(String body) {
    try {
      final data = jsonDecode(body) as List<dynamic>;
      return data
          .map((e) => Device.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      throw ApiException(message: 'Failed to parse device list from server response');
    }
  }
}
