import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_streamer_client/models/server.dart';

/// Persists saved servers using SharedPreferences.
class StorageService {
  static const _serversKey = 'saved_servers';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  /// Load all saved servers from local storage.
  Future<List<Server>> loadServers() async {
    final json = _prefs.getString(_serversKey);
    if (json == null) return [];

    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => Server.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Save the full list of servers to local storage.
  Future<void> saveServers(List<Server> servers) async {
    final json = jsonEncode(servers.map((s) => s.toJson()).toList());
    await _prefs.setString(_serversKey, json);
  }

  /// Clear all persisted data.
  Future<void> clearAll() async {
    await _prefs.clear();
  }
}
