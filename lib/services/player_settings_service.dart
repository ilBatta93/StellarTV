import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/player_settings.dart';

class PlayerSettingsService {
  static const _settingsKey = 'player_settings_v1';
  static const _resumeKey = 'player_resume_positions';
  static const _maxResumeEntries = 200;

  Future<PlayerSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null) return PlayerSettings();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return PlayerSettings.fromJson(decoded);
      }
    } on FormatException {
      // Corrupt payload: fall through to defaults.
    }
    return PlayerSettings();
  }

  Future<void> save(PlayerSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_settingsKey);
  }

  Future<Map<String, int>> _resumeMap(SharedPreferences prefs) async {
    final raw = prefs.getString(_resumeKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          for (final e in decoded.entries)
            if (e.value is num) e.key.toString(): (e.value as num).toInt(),
        };
      }
    } on FormatException {
      return {};
    }
    return {};
  }

  Future<Duration?> getResumePosition(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = (await _resumeMap(prefs))[key];
    return ms == null ? null : Duration(milliseconds: ms);
  }

  Future<void> saveResumePosition(String key, Duration? position) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _resumeMap(prefs);
    map.remove(key);
    if (position != null) map[key] = position.inMilliseconds;
    while (map.length > _maxResumeEntries) {
      map.remove(map.keys.first);
    }
    await prefs.setString(_resumeKey, jsonEncode(map));
  }

  Future<void> clearResumePositions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_resumeKey);
  }
}
