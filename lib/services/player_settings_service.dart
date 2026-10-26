import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/player_settings.dart';
import 'sync_hooks.dart';
import 'device_type_service.dart';

enum PlayerSettingsScope { shared, liveTv, filmSeriesTv }

class PlayerSettingsService {
  static const _settingsKey = 'player_settings_v1';
  static const autoNextKey = 'ui_auto_next_episode';
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
    if (raw == null) {
      return _finish(
        await _common(PlayerSettings(), prefs, scope),
        scope,
        existed: false,
      );
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final settings = PlayerSettings.fromJson(decoded);
        // One-time switch of TV live channels to mpv (see _liveDefaults);
        // later choices of the user are kept.
        if (scope == PlayerSettingsScope.liveTv &&
            decoded['liveEngineV'] != 6) {
          _liveDefaults(settings);
          await save(settings, scope: scope);
        }
        return await _finish(
          await _common(settings, prefs, scope),
          scope,
          existed: true,
        );
      }
    } on FormatException {
      // Corrupt payload: fall through to defaults.
    }
    return _finish(
      await _common(PlayerSettings(), prefs, scope),
      scope,
      existed: false,
    );
  }

  /// Rewrites a millisecond slider into the byte count mpv already used,
  /// once, so the screen and the engine share the same number.
  Future<PlayerSettings> _finish(
    PlayerSettings settings,
    PlayerSettingsScope scope, {
    required bool existed,
  }) async {
    final tv = DeviceTypeService.isTv;
    final live = PlayerSettings.migrateCacheBytes(
      settings.liveCachingMs,
      live: true,
      tv: tv,
    );
    final network = PlayerSettings.migrateCacheBytes(
      settings.networkCachingMs,
      live: false,
      tv: tv,
    );
    if (live == settings.liveCachingMs &&
        network == settings.networkCachingMs) {
      return settings;
    }
    settings.liveCachingMs = live;
    settings.networkCachingMs = network;
    if (existed) await save(settings, scope: scope);
    return settings;
  }

  Future<PlayerSettings> _common(
    PlayerSettings settings,
    SharedPreferences prefs,
    PlayerSettingsScope scope,
  ) async {
    if (scope == PlayerSettingsScope.liveTv) return settings;
    final shared = prefs.getBool(autoNextKey);
    if (shared == null) {
      // Prefer the existing TV VOD choice even if live/shared loads first.
      final vodRaw = prefs.getString(_key(PlayerSettingsScope.filmSeriesTv));
      if (vodRaw != null) {
        try {
          final vod = jsonDecode(vodRaw);
          if (vod is Map && vod['autoNextEpisode'] is bool) {
            settings.autoNextEpisode = vod['autoNextEpisode'] as bool;
          }
        } on FormatException {
          /* Keep the current validated settings. */
        }
      }
      await prefs.setBool(autoNextKey, settings.autoNextEpisode);
    } else {
      settings.autoNextEpisode = shared;
    }
    return settings;
  }

  Future<void> setAutoNextEpisode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(autoNextKey, value);
    SyncHooks.settingsChanged();
  }

  /// TV live playback starts with mpv. ExoPlayer stays the automatic
  /// fallback when mpv cannot open the stream. Preview and MultiView keep
  /// their own ExoPlayer start and are not affected here.
  static void _liveDefaults(PlayerSettings s) {
    if (!DeviceTypeService.isTv) return;
    s.primaryEngine = PlayerEngineType.mediakit;
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
    final tv = DeviceTypeService.isTv;
    defaults.liveCachingMs = PlayerSettings.migrateCacheBytes(
      defaults.liveCachingMs,
      live: true,
      tv: tv,
    );
    defaults.networkCachingMs = PlayerSettings.migrateCacheBytes(
      defaults.networkCachingMs,
      live: false,
      tv: tv,
    );
    await save(defaults, scope: scope);
    if (scope != PlayerSettingsScope.liveTv)
      await setAutoNextEpisode(defaults.autoNextEpisode);
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
