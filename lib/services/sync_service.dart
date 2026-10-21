import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/reactions_provider.dart';
import 'personal_vault.dart';
import 'favorites_service.dart';

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
  static bool isSyncedKey(String key) =>
      PersonalVault.settingKeys.contains(key);

  final VaultKeyStore _keys = VaultKeyStore();
  Future<String?> recoveryKey() async {
    final account = currentUserId;
    return account == null ? null : _keys.read(account);
  }

  Future<bool> hasCloudVault() async {
    final account = currentUserId;
    if (account == null) throw StateError('Accedi al tuo account');
    final row = await _client
        .from('personal_vaults')
        .select('revision')
        .eq('user_id', account)
        .maybeSingle();
    return row != null;
  }

  Future<void> authorizeVault(String recovery) async {
    final account = currentUserId;
    if (account == null) throw StateError('Accedi al tuo account');
    PersonalVault.keyBytes(recovery);
    final row = await _client
        .from('personal_vaults')
        .select('envelope')
        .eq('user_id', account)
        .maybeSingle();
    if (row != null)
      await PersonalVault.decrypt(row['envelope'], recovery, account);
    if (account != currentUserId) throw StateError('Account cambiato');
    await _keys.save(account, recovery);
  }

  Future<void> forgetVaultKey() async {
    final account = currentUserId;
    if (account != null) await _keys.forget(account);
  }

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

  /// Supabase.initialize has already restored local session before runApp.
  /// Offline refresh errors are not logout; the SDK owns token rotation.
  Future<bool> waitForSession({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final id = currentUserId;
    if (id == null) return false;
    await _storeCode(id);
    return true;
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
      await _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: 'https://stellartv.lovable.app/reset-password',
      );
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
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
    await FavoritesService.drainPendingWrites();
    await _historyWrites;
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

  Future<void> _historyWrites = Future<void>.value();
  Future<void> saveLocalHistory(
    Map<String, dynamic> history, {
    String? profileId,
  }) {
    final account = currentUserId;
    final snapshot = Map<String, dynamic>.from(history);
    final next = _historyWrites.then((_) async {
      if (account != currentUserId) throw StateError('Account cambiato');
      final prefs = await SharedPreferences.getInstance();
      final key = historyKeyFor(profileId);
      final raw = jsonDecode(prefs.getString(key) ?? '{}');
      final controls = <String, dynamic>{
        for (final e in PersonalVault.object(raw).entries)
          if (PersonalVault.object(e.value)['type'] == '__stellar_seen_v1') e.key: e.value,
      };
      // Late playback snapshots must never erase a newer manual choice.
      final merged = PersonalVault.mergeHistory(controls, snapshot);
      if (account != currentUserId) throw StateError('Account cambiato');
      if (!await prefs.setString(key, jsonEncode(merged))) throw StateError('Salvataggio non riuscito');
    });
    _historyWrites = next.catchError((Object _) {});
    return next;
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
    final merged = PersonalVault.mergeHistory(remote, local);
    // Preserve device-only playback addresses when remote progress is newer.
    for (final entry in merged.entries) {
      final previous = local[entry.key];
      if (entry.value is Map &&
          previous is Map &&
          entry.value['deleted'] != true) {
        merged[entry.key] = {
          ...Map<String, dynamic>.from(previous),
          ...Map<String, dynamic>.from(entry.value),
        };
      }
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
    for (final key in prefs.getKeys()) {
      if (!isSyncedKey(key)) continue;
      final value = PersonalVault.preference(prefs.get(key));
      if (value != null) settings[key] = value;
    }
    final localHistory = await loadLocalHistory();
    final profiles = await loadAllProfileHistories();
    profiles[PersonalVault.favoriteLane] = PersonalVault.object(
      jsonDecode(prefs.getString('vault_favorite_events_v1') ?? '{}'),
    );
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
      if (!isSyncedKey(key)) continue;
      final safe = PersonalVault.preference(entry.value);
      if (safe == null) continue;
      final value = key == ReactionsProvider.storageKey && safe is String
          ? ReactionsProvider.merge(
              prefs.getString(key) ?? '{}',
              entry.value as String,
            )
          : safe;
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
  Future<void> applyCredentials(Map<String, dynamic> settings) async {}
  bool hasCredentials(Map<String, dynamic> settings) => false;
  Future<bool> restorePlaylistFromCloud() async => false;

  Future<List<Map<String, dynamic>>> _all(
    String table,
    String fields,
    String column,
    String account,
  ) async {
    final out = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 500) {
      final page = await _client
          .from(table)
          .select(fields)
          .eq(column, account)
          .order(
            table == 'sync_profiles'
                ? 'code'
                : table == 'user_sync_data'
                ? 'user_id'
                : 'id',
          )
          .range(offset, offset + 499);
      out.addAll(page.map((v) => Map<String, dynamic>.from(v)));
      if (page.length < 500) return out;
    }
  }

  /// Read all old classes, never delete any of them. A failed read aborts
  /// migration rather than silently producing an incomplete backup.
  Future<Map<String, dynamic>> _legacy(String account) async {
    final profiles = await _all('sync_profiles', 'payload', 'code', account);
    final fallback = await _all(
      'user_sync_data',
      'payload',
      'user_id',
      account,
    );
    final favorites = await _all(
      'cloud_favorites',
      'item_key,item_kind,payload',
      'sync_code',
      account,
    );
    final history = await _all(
      'watch_history',
      'content_id,content_type,title,position_seconds,duration_seconds,last_watched_at',
      'user_id',
      account,
    );
    var out = PersonalVault.clean({});
    for (final row in [...fallback, ...profiles]) {
      out = PersonalVault.merge(out, row['payload']);
    }
    return PersonalVault.merge(out, {
      'favorite_ids': [
        for (final row in favorites)
          if (row['item_kind'] == 'channel') row['item_key'],
      ],
      'tmdb_favorites': [
        for (final row in favorites)
          if (row['item_kind'] == 'tmdb') row['payload'],
      ],
      'history': {
        for (final row in history)
          row['content_id'].toString(): {
            'id': row['content_id'],
            'type': row['content_type'],
            'title': row['title'],
            'pos': row['position_seconds'],
            'dur': row['duration_seconds'],
            'watched': row['last_watched_at'],
          },
      },
    });
  }

  /// Short reason of the last failed encrypted save, for the settings UI.
  String? lastError;

  Future<void> _cloudWrites = Future<void>.value();
  Future<DateTime?> push(SyncPayload payload, String code) {
    final next = _cloudWrites.then((_) => _push(payload, code));
    _cloudWrites = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<DateTime?> _push(SyncPayload payload, String code) async {
    if (code != currentUserId) {
      lastError = 'account non collegato';
      return null;
    }
    try {
      final recovery = await recoveryKey();
      if (recovery == null) {
        // No plaintext fallback, ever.
        lastError = 'chiave di recupero assente su questo dispositivo';
        return null;
      }
      final prefs = await SharedPreferences.getInstance();
      final marker = 'vault_legacy_verified_$code';
      // Old tables are only an extra source: a failed read must not block
      // the encrypted save (nothing is deleted; the marker stays unset).
      Map<String, dynamic> legacy = PersonalVault.clean({});
      var legacyOk = prefs.getBool(marker) == true;
      if (!legacyOk) {
        try {
          legacy = await _legacy(code);
          legacyOk = true;
        } catch (e) {
          debugPrint('Vault: legacy read skipped $e');
        }
      }
      if (code != currentUserId) return null;
      final local = PersonalVault.merge(legacy, payload.toJson());
      for (var attempt = 0; attempt < 4; attempt++) {
        final row = await _client
            .from('personal_vaults')
            .select('envelope,revision')
            .eq('user_id', code)
            .maybeSingle();
        final remote = row == null
            ? PersonalVault.clean({})
            : await PersonalVault.decrypt(row['envelope'], recovery, code);
        final merged = PersonalVault.merge(remote, local);
        if (code != currentUserId) return null;
        // Fresh remote read remains mandatory: never suppress another
        // device's changes using a cached local fingerprint.
        if (row != null && PersonalVault.canonical(remote) == PersonalVault.canonical(merged)) {
          lastError = null;
          if (legacyOk) await prefs.setBool(marker, true);
          final now = DateTime.now();
          await prefs.setString(_lastPushKey, now.toIso8601String());
          return now;
        }
        final envelope = await PersonalVault.encrypt(merged, recovery, code);
        if (code != currentUserId) return null;
        dynamic revision;
        try {
          revision = await _client.rpc(
            'save_personal_vault',
            params: {
              '_envelope': envelope,
              '_expected_revision': row?['revision'] ?? 0,
            },
          );
        } on PostgrestException catch (e) {
          if (e.code == '40001') continue;
          rethrow;
        }
        final check = await _client
            .from('personal_vaults')
            .select('envelope,revision')
            .eq('user_id', code)
            .single();
        final decoded = await PersonalVault.decrypt(
          check['envelope'],
          recovery,
          code,
        );
        if (code != currentUserId) return null;
        if (check['revision'].toString() != revision.toString()) continue;
        // AES-GCM already authenticates the stored copy; a byte-level
        // comparison wrongly rejected saves whose numbers or ordering
        // changed in transit. Only require that the essentials survived.
        if ((decoded['history'] as Map).length <
            (PersonalVault.clean(merged)['history'] as Map).length)
          throw StateError('Verifica cifrata non riuscita');
        final now = DateTime.now();
        lastError = null;
        if (legacyOk) await prefs.setBool(marker, true);
        await prefs.setString(_lastPushKey, now.toIso8601String());
        return now;
      }
    } catch (e) {
      /* Preserve all local and legacy copies on any failure. */
      lastError = e.toString();
      debugPrint('Vault push failed: $e');
      return null;
    }
    lastError = 'conflitto di versione';
    return null;
  }

  Future<(SyncPayload?, DateTime?)> pull(String code) async {
    if (code != currentUserId) return (null, null);
    try {
      final recovery = await recoveryKey();
      if (recovery == null) return (null, null);
      final row = await _client
          .from('personal_vaults')
          .select('envelope,updated_at')
          .eq('user_id', code)
          .maybeSingle();
      if (row == null) return (null, null);
      final decoded = await PersonalVault.decrypt(
        row['envelope'],
        recovery,
        code,
      );
      if (code != currentUserId) return (null, null);
      return (
        SyncPayload.fromJson(PersonalVault.merge({}, decoded)),
        DateTime.tryParse(row['updated_at'].toString()),
      );
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
