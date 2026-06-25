import 'device.dart';

/// Connection status of a saved server.
enum ServerStatus { connected, connecting, offline }

/// Represents a media server the client can connect to.
class Server {
  final String id;
  String name;
  final String address;
  final String psk;
  final String? tlsFingerprint;
  final bool isTls;
  ServerStatus status;
  final List<Device> devices;
  final DateTime? lastConnected;

  Server({
    required this.id,
    required this.name,
    required this.address,
    required this.psk,
    this.tlsFingerprint,
    this.isTls = false,
    this.status = ServerStatus.offline,
    this.devices = const [],
    this.lastConnected,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'psk': psk,
        'tlsFingerprint': tlsFingerprint,
        'isTls': isTls,
        'status': status.name,
        'devices': devices.map((d) => d.toJson()).toList(),
        'lastConnected': lastConnected?.toIso8601String(),
      };

  factory Server.fromJson(Map<String, dynamic> json) => Server(
        id: json['id'] as String,
        name: json['name'] as String,
        address: json['address'] as String,
        psk: json['psk'] as String,
        tlsFingerprint: json['tlsFingerprint'] as String?,
        isTls: json['isTls'] as bool? ?? false,
        status: ServerStatus.values.byName(
            json['status'] as String? ?? 'offline'),
        devices: (json['devices'] as List<dynamic>?)
                ?.map((d) => Device.fromJson(d as Map<String, dynamic>))
                .toList() ??
            [],
        lastConnected: json['lastConnected'] != null
            ? DateTime.parse(json['lastConnected'] as String)
            : null,
      );

  Server copyWith({
    String? name,
    ServerStatus? status,
    List<Device>? devices,
    DateTime? lastConnected,
  }) {
    return Server(
      id: id,
      name: name ?? this.name,
      address: address,
      psk: psk,
      tlsFingerprint: tlsFingerprint,
      isTls: isTls,
      status: status ?? this.status,
      devices: devices ?? this.devices,
      lastConnected: lastConnected ?? this.lastConnected,
    );
  }
}
