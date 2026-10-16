import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/ui_settings.dart';
import '../providers/reactions_provider.dart';

/// A snapshot of everything the user cares about, serializable to JSON.
class SyncPayload {
  final Map<String, dynamic> history;
  final List<String> favoriteIds;
  final List<Map<String, dynamic>> tmdbFavorites;
  final Map<String, dynamic> settings;

  /// Watch history of each profile (key: profile id), kept private per
  /// profile. [history] is the history used when no profile is selected.
  final Map<String, dynamic> profileHistories;

  const SyncPayload({
    required this.history,
    required this.favoriteIds,
    required this.tmdbFavorites,
    required this.settings,
    this.profileHistories = const {},
  });

  Map<String, dynamic> toJson() => {
    'v': 3,
    'profile_histories': profileHistories,
    'history': history,
    'favorite_ids': favoriteIds,
    'tmdb_favorites': tmdbFavorites,
    'settings': settings,
  };

  static SyncPayload fromJson(Map<String, dynamic> json) => SyncPayload(
    history: (json['history'] as Map<String, dynamic>?) ?? const {},
    favoriteIds: ((json['favorite_ids'] as List?) ?? const [])
        .cast<String>()
        .toList(),
    tmdbFavorites: ((json['tmdb_favorites'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(),
    settings: (json['settings'] as Map<String, dynamic>?) ?? const {},
    profileHistories:
        (json['profile_histories'] as Map<String, dynamic>?) ?? const {},
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
  static const _uiKeys = [
    'kids_pin',
    'ui_accent',
    'ui_grid_size',
    'theme_mode',
    'ui_animations',
    'ui_show_posters',
    'ui_compact',
    UiSettings.sectionOrderKey,
    UiSettings.startSectionKey,
    UiSettings.multiViewLayoutKey,
    'show_adult_content',
    'hidden_categories',
    'playlist_refresh_minutes',
    'epg_use_playlist',
    'epg_sources',
    'epg_refresh_minutes',
    'expiry_reminders_v1',
    ReactionsProvider.storageKey,
  ];
  static const _syncedKeys = [
    ..._credentialsKeys,
    'player_settings_v1',
    'player_resume_positions',
    ..._uiKeys,
    'favorite_channels',
    'favorite_tmdb_items',
  ];

  /// The cloud "code" is now the id of the signed-in account: every row in
  /// the cloud is tied to it and protected so only that account can read it.
  String? get currentUserId => _client.auth.currentUser?.id;
  String? get currentEmail => _client.auth.currentUser?.email;

  /// Returns the account id; throws when nobody is signed in.
  Future<String> ensureCode() async {
    final id = currentUserId;
    if (id == null)
      throw StateError('Accedi al tuo account per usare il cloud.');
    await _storeCode(id);
    return id;
  }

  Future<String?> getStoredCode() async {
    final id = currentUserId;
    if (id != null) await _storeCode(id);
    return id;
  }

  Future<void> _storeCode(String id) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(codeKey) != id) await prefs.setString(codeKey, id);
  }

  Future<String?> signIn(String email, String password) async {
    try {
      await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      await getStoredCode();
      return null;
    } on AuthException catch (e) {
      return _authMessage(e);
    } catch (_) {
      return 'Accesso non riuscito. Controlla la connessione.';
    }
  }

  Future<String?> signUp(String email, String password) async {
    try {
      final res = await _client.auth.signUp(
        email: email.trim(),
        password: password,
      );
      if (res.session == null) return confirmPending;
      await getStoredCode();
      return null;
    } on AuthException catch (e) {
      return _authMessage(e);
    } catch (_) {
      return 'Registrazione non riuscita. Controlla la connessione.';
    }
  }

  /// Returned by [signUp] when the account waits for email confirmation.
  static const confirmPending = '__confirm_email_pending__';

  /// Sends the signup confirmation email again.
  Future<String?> resendConfirmation(String email) async {
    try {
      await _client.auth.resend(type: OtpType.signup, email: email.trim());
      return null;
    } on AuthException catch (e) {
      return _authMessage(e);
    } catch (_) {
      return 'Invio non riuscito. Controlla la connessione.';
    }
  }

  Future<String?> resetPassword(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email.trim());
      return null;
    } on AuthException catch (e) {
      return _authMessage(e);
    } catch (_) {
      return 'Invio non riuscito. Controlla la connessione.';
    }
  }

  static const notConfirmed =
      'Email non ancora confermata. Apri il link che ti abbiamo inviato, poi accedi.';

  String _authMessage(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('not confirmed')) return notConfirmed;
    if (m.contains('rate limit') || m.contains('security purposes')) {
      return 'Troppi tentativi: attendi un minuto e riprova.';
    }
    if (m.contains('invalid login')) return 'Email o password non corretti.';
    if (m.contains('already registered') || m.contains('already exists')) {
      return 'Esiste già un account con questa email: accedi.';
    }
    if (m.contains('password') &&
        (m.contains('weak') || m.contains('pwned') || m.contains('leaked'))) {
      return 'Password troppo debole o già trapelata online: scegline un\'altra.';
    }
    if (m.contains('at least'))
      return 'La password deve avere almeno 6 caratteri.';
    if (m.contains('email') && m.contains('invalid'))
      return 'Email non valida.';
    return e.message;
  }

  /// Signs out and wipes every local copy of account data from this device.
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  // ----- local persistence -----

  static String historyKeyFor(String? profileId) =>
      profileId == null || profileId.isEmpty
      ? _localHistoryKey
      : '${_localHistoryKey}__$profileId';

  Future<Map<String, dynamic>> loadLocalHistory({String? profileId}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(historyKeyFor(profileId));
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  Future<void> saveLocalHistory(
    Map<String, dynamic> history, {
    String? profileId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(historyKeyFor(profileId), jsonEncode(history));
  }

  /// Every per-profile history stored on this device.
  Future<Map<String, dynamic>> loadAllProfileHistories() async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = '${_localHistoryKey}__';
    final out = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(prefix)) continue;
      try {
        final d = jsonDecode(prefs.getString(key) ?? '{}');
        if (d is Map<String, dynamic>) out[key.substring(prefix.length)] = d;
      } catch (_) {}
    }
    return out;
  }

  /// Merges a remote history map into local storage (newest `watched` wins).
  Future<Map<String, dynamic>> mergeHistoryInto(
    Map<String, dynamic> remote, {
    String? profileId,
  }) async {
    final local = await loadLocalHistory(profileId: profileId);
    final merged = {...local};
    for (final e in remote.entries) {
      final r = e.value;
      if (r is! Map<String, dynamic>) continue;
      final l = merged[e.key];
      final rw = DateTime.tryParse(r['watched']?.toString() ?? '');
      final lw = l is Map
          ? DateTime.tryParse(l['watched']?.toString() ?? '')
          : null;
      if (lw == null || (rw != null && rw.isAfter(lw))) merged[e.key] = r;
    }
    await saveLocalHistory(merged, profileId: profileId);
    return merged;
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
    final profiles = await loadAllProfileHistories();
    return SyncPayload(
      history: localHistory,
      profileHistories: profiles,
      favoriteIds: favoriteIds?.toList() ?? const [],
      tmdbFavorites: tmdbFavorites ?? const [],
      settings: _dropNulls(settings),
    );
  }

  Map<String, dynamic> _dropNulls(Map<String, dynamic> map) =>
      Map.fromEntries(map.entries.where((e) => e.value != null));

  /// Writes a cloud snapshot into local storage. With [overwrite] (the cloud
  /// copy is newer than this device's last upload) values replace local
  /// ones, so a change made on another device reaches every device;
  /// otherwise only keys missing locally are filled in.
  Future<bool> applySnapshotSettings(
    Map<String, dynamic> settings, {
    bool overwrite = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var changed = false;
    for (final entry in settings.entries) {
      final key = entry.key;
      if (!_syncedKeys.contains(key) || key == 'local_watch_history') continue;
      final value = key == ReactionsProvider.storageKey && entry.value is String
          ? ReactionsProvider.merge(
              prefs.getString(key) ?? '{}',
              entry.value as String,
            )
          : entry.value;
      final write =
          key == ReactionsProvider.storageKey ||
          overwrite ||
          !prefs.containsKey(key);
      if (!write || prefs.get(key).toString() == value.toString()) continue;
      changed = true;
      if (value is String) {
        await prefs.setString(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is List) {
        await prefs.setStringList(key, value.whereType<String>().toList());
      }
    }
    return changed;
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

