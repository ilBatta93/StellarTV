import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A snapshot of everything the user cares about, serializable to JSON.
class SyncPayload {
  final Map<String, dynamic> history;
  final List<String> favoriteIds;
  final List<Map<String, dynamic>> tmdbFavorites;
  final Map<String, dynamic> settings;

  const SyncPayload({
    required this.history,
    required this.favoriteIds,
    required this.tmdbFavorites,
    required this.settings,
  });

  Map<String, dynamic> toJson() => {
        'v': 2,
        'history': history,
        'favorite_ids': favoriteIds,
        'tmdb_favorites': tmdbFavorites,
        'settings': settings,
      };

  static SyncPayload fromJson(Map<String, dynamic> json) => SyncPayload(
        history: (json['history'] as Map<String, dynamic>?) ?? const {},
        favoriteIds:
            ((json['favorite_ids'] as List?) ?? const []).cast<String>().toList(),
        tmdbFavorites: ((json['tmdb_favorites'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(),
        settings: (json['settings'] as Map<String, dynamic>?) ?? const {},
      );
}

/// Handles everything for the optional cloud sync: local persistence, pairing
/// code generation, push and pull against the `sync_profiles` table.
class SyncService {
  SyncService(this._client);

  final SupabaseClient _client;

  static const codeKey = 'sync_code';
  static const _localHistoryKey = 'local_watch_history';
  static const _lastPushKey = 'sync_last_push';
  static const _lastPullKey = 'sync_last_pull';
  static const _credentialsKeys = [
    'auth_method',
    'xtream_server',
    'xtream_username',
    'xtream_password',
    'playlist_url',
  ];
  static const _uiKeys = ['ui_accent', 'ui_grid_size', 'theme_mode'];
  static const _syncedKeys = [
    ..._credentialsKeys,
    'player_settings_v1',
    'player_resume_positions',
    'local_watch_history',
    ..._uiKeys,
    'favorite_channels',
    'favorite_tmdb_items',
  ];

  /// The pairing code for this profile; created lazily on first access.
  Future<String> ensureCode() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(codeKey);
    if (existing != null && existing.length == 8) return existing;
    final code = _generateCode();
    await prefs.setString(codeKey, code);
    return code;
  }

  Future<String?> getStoredCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(codeKey);
  }

  Future<void> setCodeManually(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(codeKey, code.toUpperCase().trim());
  }

  Future<void> clearCode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(codeKey);
  }

  String _generateCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(8, (_) => alphabet[rnd.nextInt(alphabet.length)]).join();
  }

  // ----- local persistence -----

  Future<Map<String, dynamic>> loadLocalHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localHistoryKey);
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  Future<void> saveLocalHistory(Map<String, dynamic> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localHistoryKey, jsonEncode(history));
  }

  // ----- snapshot collection -----

  Future<SyncPayload> collectSnapshot({
    List<String>? favoriteIds,
    List<Map<String, dynamic>>? tmdbFavorites,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final settings = <String, dynamic>{};
    for (final key in _syncedKeys) {
      if (!prefs.containsKey(key)) continue;
      settings[key] = prefs.get(key);
    }
    final localHistory = await loadLocalHistory();
    return SyncPayload(
      history: localHistory,
      favoriteIds: favoriteIds?.toList() ?? const [],
      tmdbFavorites: tmdbFavorites ?? const [],
      settings: _dropNulls(settings),
    );
  }

  Map<String, dynamic> _dropNulls(Map<String, dynamic> map) =>
      Map.fromEntries(map.entries.where((e) => e.value != null));

  /// Writes a cloud snapshot into local storage. Only fills keys the cloud
  /// has and local does not, so restoring never erases newer local edits.
  Future<void> applySnapshotSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in settings.entries) {
      final key = entry.key;
      if (!_syncedKeys.contains(key)) continue;
      final value = entry.value;
      if (value is String && !prefs.containsKey(key)) {
        await prefs.setString(key, value);
      } else if (value is bool && !prefs.containsKey(key)) {
        await prefs.setBool(key, value);
      } else if (value is int && !prefs.containsKey(key)) {
        await prefs.setInt(key, value);
      } else if (value is List && !prefs.containsKey(key)) {
        await prefs.setStringList(
            key, value.whereType<String>().toList());
      }
    }
  }

  /// Overwrites local storage with cloud credentials (used when the local
  /// device has no playlist configured yet).
  Future<void> applyCredentials(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _credentialsKeys) {
      final value = settings[key];
      if (value is String) {
        await prefs.setString(key, value);
      } else {
        await prefs.remove(key);
        if (key == 'auth_method') continue;
      }
    }
  }

  bool hasCredentials(Map<String, dynamic> settings) =>
      settings['auth_method'] is String;

  // ----- cloud push/pull -----

  Future<DateTime?> push(SyncPayload payload, String code) async {
    try {
      await _client.from('sync_profiles').upsert({
        'code': code,
        'payload': payload.toJson(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastPushKey, now.toIso8601String());
      return now;
    } catch (_) {
      return null;
    }
  }

  Future<(SyncPayload?, DateTime?)> pull(String code) async {
    try {
      final rows = await _client
          .from('sync_profiles')
          .select('payload, updated_at')
          .eq('code', code)
          .limit(1);
      if (rows.isEmpty) return (null, null);
      final row = rows.first;
      final payloadJson = row['payload'];
      final updated = DateTime.tryParse(row['updated_at']?.toString() ?? '');
      if (payloadJson is! Map<String, dynamic>) return (null, null);
      return (SyncPayload.fromJson(payloadJson), updated);
    } catch (_) {
      return (null, null);
    }
  }

  Future<DateTime?> lastPush() async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(prefs.getString(_lastPushKey) ?? '');
  }

  Future<DateTime?> lastPull() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return DateTime.tryParse(prefs.getString(_lastPullKey) ?? '');
  }

  Future<void> markPulled() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastPullKey, DateTime.now().toIso8601String());
  }
}
