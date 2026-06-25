/// Type of media device.
enum DeviceType { video, audio }

/// Represents a single media device (camera, mic, etc.) on a server.
class Device {
  final String id;
  final String name;
  final DeviceType type;

  const Device({
    required this.id,
    required this.name,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
      };

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        id: json['id'] as String,
        name: json['name'] as String,
        type: DeviceType.values.byName(json['type'] as String? ?? 'video'),
      );
}
