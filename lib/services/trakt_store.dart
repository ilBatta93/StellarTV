import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/trakt_policy.dart';
import 'device_json_file.dart';

/// What the Trakt link keeps on this device, per profile:
/// - the sign-in, in secure storage (`trakt_session_v1:`), left out of the
///   phone backup (DeviceBackupPolicy.keepsSecret);
/// - changes not yet sent and the last activity stamps, in preferences
///   (`trakt_` keys, left out of the backup too);
/// - the remote state, in a support file.
/// Nothing goes to the cloud.
class TraktStore {
  const TraktStore();

  // Same options as settings_service.dart: one store for the app's secrets.
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static String _profile(String? profileId) =>
      (profileId == null || profileId.isEmpty) ? '_' : profileId;

  Future<TraktSession?> session(String? profileId) async {
    try {
      final raw = await _storage.read(
        key: 'trakt_session_v1:${_profile(profileId)}',
      );
      if (raw == null) return null;
      return TraktSession.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSession(String? profileId, TraktSession? session) async {
    final key = 'trakt_session_v1:${_profile(profileId)}';
    if (session == null) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: jsonEncode(session.toJson()));
    }
  }

  Future<List<TraktPending>> pending(String? profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('trakt_outbox_v1:${_profile(profileId)}');
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [for (final item in list) ?TraktPending.fromJson(item)];
    } catch (_) {
      return [];
    }
  }

  Future<void> savePending(String? profileId, List<TraktPending> items) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'trakt_outbox_v1:${_profile(profileId)}';
    if (items.isEmpty) {
      await prefs.remove(key);
    } else {
      // A long offline stretch keeps the newest 2000 choices.
      final kept = items.length > 2000
          ? items.sublist(items.length - 2000)
          : items;
      await prefs.setString(
        key,
        jsonEncode([for (final p in kept) p.toJson()]),
      );
    }
  }

  Future<TraktActivity?> activity(String? profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('trakt_activity_v1:${_profile(profileId)}');
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      return TraktActivity({
        for (final e in map.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      });
    } catch (_) {
      return null;
    }
  }

  Future<void> saveActivity(String? profileId, TraktActivity? activity) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'trakt_activity_v1:${_profile(profileId)}';
    if (activity == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, jsonEncode(activity.stamps));
    }
  }

  Future<DateTime?> lastSync(String? profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('trakt_last_sync_v1:${_profile(profileId)}');
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> saveLastSync(String? profileId, DateTime? at) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'trakt_last_sync_v1:${_profile(profileId)}';
    if (at == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, at.toUtc().toIso8601String());
    }
  }

  Future<bool> scrobbleEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('trakt_scrobble_v1') ?? true;
  }

  Future<void> setScrobbleEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('trakt_scrobble_v1', value);
  }

  DeviceJsonFile _remoteFile(String? profileId) =>
      DeviceJsonFile('trakt_remote_${_profile(profileId)}');

  Future<TraktRemoteState> remote(String? profileId) async =>
      TraktRemoteState.fromJson(await _remoteFile(profileId).read());

  Future<void> saveRemote(String? profileId, TraktRemoteState? state) =>
      _remoteFile(profileId).write(state?.toJson());

  /// Forgets everything of [profileId] (disconnect).
  Future<void> clear(String? profileId) async {
    await saveSession(profileId, null);
    await savePending(profileId, const []);
    await saveActivity(profileId, null);
    await saveLastSync(profileId, null);
    await saveRemote(profileId, null);
  }
}
