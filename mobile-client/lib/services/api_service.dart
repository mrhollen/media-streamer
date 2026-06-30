import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io' show SocketException;
import 'package:flutter/foundation.dart';
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

  ApiService() {
    debugPrint('[${DateTime.now().toString()}] [ApiService] Constructor: ApiService initialised');
  }

  /// Build the base URL for a server address.
  String _baseUrl(String address, {bool isTls = false}) {
    final scheme = isTls ? 'https' : 'http';
    // Ensure address doesn't already contain a scheme
    final clean = address.split('://').last;
    final base = '$scheme://$clean';
    debugPrint('[${DateTime.now().toString()}] [ApiService] _baseUrl: address="$address" isTls=$isTls => "$base"');
    return base;
  }

  /// Common auth headers for every request.
  Map<String, String> _authHeaders(String psk) {
    final headers = <String, String>{
      'Authorization': 'Bearer $psk',
      'Content-Type': 'application/json',
    };
    debugPrint('[${DateTime.now().toString()}] [ApiService] _authHeaders: PSK header present=${headers.containsKey('Authorization')}');
    return headers;
  }

  /// Fetch the list of devices available on a server.
  ///
  /// Calls `GET /devices` on the media streaming server.
  Future<List<Device>> fetchDevices(
    String address,
    String psk, {
    bool isTls = false,
  }) async {
    final url = Uri.parse('${_baseUrl(address, isTls: isTls)}/devices');
    debugPrint('[${DateTime.now().toString()}] [ApiService] fetchDevices: GET "$url"');

    try {
      debugPrint('[${DateTime.now().toString()}] [ApiService] fetchDevices: sending HTTP request (timeout=${_timeout.inSeconds}s)');
      final response = await http
          .get(url, headers: _authHeaders(psk))
          .timeout(_timeout);

      debugPrint('[${DateTime.now().toString()}] [ApiService] fetchDevices: HTTP response statusCode=${response.statusCode}');

      switch (response.statusCode) {
        case 200:
          final devices = _parseDeviceList(response.body);
          debugPrint('[${DateTime.now().toString()}] [ApiService] fetchDevices: parsed ${devices.length} devices from response');
          for (final device in devices) {
            debugPrint('[${DateTime.now().toString()}] [ApiService] fetchDevices:   device id="${device.id}" name="${device.name}"');
          }
          return devices;

        case 401:
          debugPrint('[${DateTime.now().toString()}] [ApiService] fetchDevices: HTTP 401 — throwing InvalidPSKException');
          throw InvalidPSKException();

        default:
          debugPrint('[${DateTime.now().toString()}] [ApiService] fetchDevices: unexpected statusCode=${response.statusCode} — throwing ApiException');
          throw ApiException(
            message: 'Unexpected response: ${response.statusCode}',
            statusCode: response.statusCode,
          );
      }
    } on SocketException catch (e, st) {
      debugPrint('[${DateTime.now().toString()}] [ApiService] fetchDevices: SocketException — $e');
      debugPrint('[${DateTime.now().toString()}] [ApiService] fetchDevices: stackTrace:\n$st');
      throw NetworkException(message: 'Failed to connect to $address');
    } on TimeoutException catch (e, st) {
      debugPrint('[${DateTime.now().toString()}] [ApiService] fetchDevices: TimeoutException — $e');
      debugPrint('[${DateTime.now().toString()}] [ApiService] fetchDevices: stackTrace:\n$st');
      throw ConnectionTimeoutException(message: 'Connection to $address timed out');
    } catch (e, st) {
      if (e is ApiException) {
        debugPrint('[${DateTime.now().toString()}] [ApiService] fetchDevices: rethrowing ApiException — $e');
        rethrow;
      }
      debugPrint('[${DateTime.now().toString()}] [ApiService] fetchDevices: unhandled exception — $e');
      debugPrint('[${DateTime.now().toString()}] [ApiService] fetchDevices: stackTrace:\n$st');
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
    debugPrint('[${DateTime.now().toString()}] [ApiService] pingServer: GET "$url"');

    try {
      debugPrint('[${DateTime.now().toString()}] [ApiService] pingServer: sending HTTP request (timeout=${_timeout.inSeconds}s)');
      final response = await http
          .get(url, headers: _authHeaders(psk))
          .timeout(_timeout);
      final result = response.statusCode == 200;
      debugPrint('[${DateTime.now().toString()}] [ApiService] pingServer: HTTP response statusCode=${response.statusCode} => result=$result');
      return result;
    } catch (e, st) {
      debugPrint('[${DateTime.now().toString()}] [ApiService] pingServer: exception — $e');
      debugPrint('[${DateTime.now().toString()}] [ApiService] pingServer: stackTrace:\n$st');
      return false;
    }
  }

  // -----------------------------------------------------------------
  // Internal helpers
  // -----------------------------------------------------------------

  List<Device> _parseDeviceList(String body) {
    debugPrint('[${DateTime.now().toString()}] [ApiService] _parseDeviceList: parsing body (length=${body.length} chars)');
    try {
      final data = jsonDecode(body) as List<dynamic>;
      debugPrint('[${DateTime.now().toString()}] [ApiService] _parseDeviceList: jsonDecode returned ${data.length} items');
      final devices = data
          .map((e) => Device.fromJson(e as Map<String, dynamic>))
          .toList();
      debugPrint('[${DateTime.now().toString()}] [ApiService] _parseDeviceList: mapped ${devices.length} Device objects');
      return devices;
    } catch (e, st) {
      debugPrint('[${DateTime.now().toString()}] [ApiService] _parseDeviceList: parse failed — $e');
      debugPrint('[${DateTime.now().toString()}] [ApiService] _parseDeviceList: stackTrace:\n$st');
      throw ApiException(message: 'Failed to parse device list from server response');
    }
  }
}
