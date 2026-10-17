import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/player_settings.dart';
import 'sync_hooks.dart';
import 'device_type_service.dart';

enum PlayerSettingsScope { shared, liveTv, filmSeriesTv }

class PlayerSettingsService {
  static const _settingsKey = 'player_settings_v1';
  static const _resumeKey = 'player_resume_positions';
  static const _maxResumeEntries = 200;

  String _key(PlayerSettingsScope scope) => switch (scope) {
    PlayerSettingsScope.shared => _settingsKey,
    PlayerSettingsScope.liveTv => 'player_settings_tv_live_v1',
    PlayerSettingsScope.filmSeriesTv => 'player_settings_tv_vod_v1',
  };

  Future<PlayerSettings> load({
    PlayerSettingsScope scope = PlayerSettingsScope.shared,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(scope));
    if (raw == null && scope != PlayerSettingsScope.shared) {
      final previous = await load();
      if (scope == PlayerSettingsScope.liveTv) _liveDefaults(previous);
      await save(previous, scope: scope);
      return previous;
    }
    if (raw == null) return PlayerSettings();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final settings = PlayerSettings.fromJson(decoded);
        // One-time switch of TV live channels to ExoPlayer (see
        // _liveDefaults); later choices of the user are kept.
        if (scope == PlayerSettingsScope.liveTv &&
            decoded['liveEngineV'] != 5) {
          _liveDefaults(settings);
          await save(settings, scope: scope);
        }
        return settings;
      }
    } on FormatException {
      // Corrupt payload: fall through to defaults.
    }
    return PlayerSettings();
  }

  /// TV live channels start with ExoPlayer, the device's native decoder:
  /// on Fire TV mpv kept a black picture while ExoPlayer drew the channel.
  /// mpv remains the automatic fallback for streams ExoPlayer rejects.
  static void _liveDefaults(PlayerSettings s) {
    if (!DeviceTypeService.isTv) return;
    s.primaryEngine = PlayerEngineType.exo;
    s.autoFallback = true;
  }

  Future<void> save(
    PlayerSettings settings, {
    PlayerSettingsScope scope = PlayerSettingsScope.shared,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(scope), jsonEncode(settings.toJson()));
    SyncHooks.settingsChanged();
  }

  Future<void> reset({
    PlayerSettingsScope scope = PlayerSettingsScope.shared,
  }) async {
    final defaults = PlayerSettings();
    if (scope == PlayerSettingsScope.liveTv) _liveDefaults(defaults);
    await save(defaults, scope: scope);
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
