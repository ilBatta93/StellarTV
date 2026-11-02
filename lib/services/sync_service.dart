import 'package:flutter/foundation.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'playback_work_policy.dart';

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

  /// When this snapshot was read from the device (not serialized).
  final DateTime? collectedAt;

  const SyncPayload({
    this.collectedAt,
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

/// Handles everything for the optional cloud sync: local persistence, account
/// session and push/pull of the encrypted `personal_vaults` copy.
class SyncService {
  SyncService(this._client);

  final SupabaseClient _client;

  static const codeKey = 'sync_code';
  static const _localHistoryKey = 'local_watch_history';
  static const _lastPushKey = 'sync_last_push';
  static const _lastPullKey = 'sync_last_pull';
  static const _lastSnapshotKey = 'sync_last_saved_snapshot';
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
    if (row != null) {
      await PersonalVault.decrypt(row['envelope'], recovery, account);
    }
    if (account != currentUserId) throw StateError('Account cambiato');
    await _keys.save(account, recovery);
    await _forgetApplied(account);
  }

  Future<void> forgetVaultKey() async {
    final account = currentUserId;
    if (account == null) return;
    await _keys.forget(account);
    await _forgetApplied(account);
    _remote = null;
  }

  // ----- revision cache -----

  /// Last decrypted cloud copy. The vault revision grows on every save (the
  /// RPC compares and increments it), so a fresh revision read that matches
  /// proves this copy is still the cloud content: no download, no decrypt.
  _RemoteVault? _remote;

  static String _appliedKey(String account, String? profileId) =>
      'vault_applied_revision_${account}_${profileId ?? ''}';

  /// Records that this device's local data already contains the cloud copy
  /// at [revision] for [profileId], so the next pull at the same revision
  /// can skip download, decrypt and merge.
  Future<void> markApplied(
    String account,
    String? profileId,
    int? revision,
  ) async {
    if (revision == null || account != currentUserId) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_appliedKey(account, profileId), revision);
  }

  Future<void> _forgetApplied(String account) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'vault_applied_revision_${account}_';
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(prefix)) await prefs.remove(key);
    }
  }

  static int? _revision(dynamic v) => v is num ? v.toInt() : null;

  /// Returns the cloud copy, downloading the envelope only when the revision
  /// differs from the cached one. [head] carries the fields of the cheap
  /// revision read (e.g. `updated_at`), or of the full read on a miss.
  Future<
    ({Map<String, dynamic> data, int? revision, Map<String, dynamic>? head})
  >
  _readRemote(
    String code,
    String recovery, {
    String headFields = 'revision',
  }) async {
    final cached = _remote;
    if (cached != null &&
        cached.account == code &&
        cached.recovery == recovery) {
      final head = await _client
          .from('personal_vaults')
          .select(headFields)
          .eq('user_id', code)
          .maybeSingle();
      if (head == null) {
        _remote = null;
        return (data: PersonalVault.clean({}), revision: null, head: null);
      }
      if (_revision(head['revision']) == cached.revision) {
        return (data: cached.data, revision: cached.revision, head: head);
      }
    }
    final fields = headFields == 'revision'
        ? 'envelope,revision'
        : 'envelope,$headFields';
    final row = await _client
        .from('personal_vaults')
        .select(fields)
        .eq('user_id', code)
        .maybeSingle();
    if (row == null) {
      _remote = null;
      return (data: PersonalVault.clean({}), revision: null, head: null);
    }
    final data = await PersonalVault.decrypt(row['envelope'], recovery, code);
    final revision = _revision(row['revision']);
    _remote = revision == null
        ? null
        : _RemoteVault(code, recovery, revision, data);
    return (data: data, revision: revision, head: row);
  }

  /// The cloud "code" is now the id of the signed-in account: every row in
  /// the cloud is tied to it and protected so only that account can read it.
  String? get currentUserId => _client.auth.currentUser?.id;
  String? get currentEmail => _client.auth.currentUser?.email;

  /// Returns the account id; throws when nobody is signed in.
  Future<String> ensureCode() async {
    final id = currentUserId;
    if (id == null) {
      throw StateError('Accedi al tuo account per usare il cloud.');
    }
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
        redirectTo: 'https://stellartv.vercel.app/reset-password',
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
    if (m.contains('at least')) {
      return 'La password deve avere almeno 6 caratteri.';
    }
    if (m.contains('email') && m.contains('invalid')) {
      return 'Email non valida.';
    }
    return e.message;
  }

  /// Signs out and wipes every local copy of account data from this device.
  Future<void> signOut() async {
    _remote = null;
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
  final Map<String, _QueuedHistory> _queuedHistory = {};

  /// Serializes preference writes. A burst for the same key keeps only the
  /// newest snapshot, so pause and exit do not rewrite the blob twice.
  Future<void> saveLocalHistory(
    Map<String, dynamic> history, {
    String? profileId,
  }) {
    final key = historyKeyFor(profileId);
    final queued = _queuedHistory[key];
    if (queued != null && !queued.started) {
      queued.account = currentUserId;
      queued.snapshot = PersonalVault.mergeHistory(queued.snapshot, history);
      return queued.done.future;
    }
    final pending = _QueuedHistory(
      currentUserId,
      Map<String, dynamic>.from(history),
    );
    _queuedHistory[key] = pending;
    final next = _historyWrites.then((_) => _writeQueuedHistory(key, pending));
    _historyWrites = next.catchError((Object _) {});
    return pending.done.future;
  }

  Future<void> _writeQueuedHistory(String key, _QueuedHistory pending) async {
    pending.started = true;
    if (identical(_queuedHistory[key], pending)) _queuedHistory.remove(key);
    try {
      if (pending.account != currentUserId) {
        throw StateError('Account cambiato');
      }
      final prefs = await SharedPreferences.getInstance();
      if (pending.account != currentUserId) {
        throw StateError('Account cambiato');
      }
      final existing = prefs.getString(key);
      final raw = jsonDecode(existing ?? '{}');
      final controls = <String, dynamic>{
        for (final e in PersonalVault.object(raw).entries)
          if (PersonalVault.object(e.value)['type'] == '__stellar_seen_v1')
            e.key: e.value,
      };
      // Late playback snapshots must never erase a newer manual choice.
      final merged = PersonalVault.mergeHistory(controls, pending.snapshot);
      final encoded = jsonEncode(merged);
      if (existing != encoded && !await prefs.setString(key, encoded)) {
        throw StateError('Salvataggio non riuscito');
      }
      if (!pending.done.isCompleted) pending.done.complete();
    } catch (error, stack) {
      if (!pending.done.isCompleted) {
        pending.done.completeError(error, stack);
      }
      Error.throwWithStackTrace(error, stack);
    }
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
    profiles[PersonalVault.profilesLane] = PersonalVault.object(
      jsonDecode(prefs.getString(profileNamesKey) ?? '{}'),
    );
    try {
      profiles[PersonalVault.reactionsLane] = PersonalVault.reactionsToLane(
        jsonDecode(prefs.getString(ReactionsProvider.storageKey) ?? '{}'),
      );
    } catch (_) {}
    return SyncPayload(
      collectedAt: DateTime.now(),
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
    final account = currentUserId;
    final base = account == null
        ? null
        : _settingsBase(prefs, account) ?? <String, dynamic>{};
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
      final local = PersonalVault.preference(prefs.get(key));
      // With a known base a key is replaced only when this device did not
      // change it since the last sync; the clock comparison stays for keys
      // never synced from here.
      final unchangedHere =
          base != null && base.containsKey(key) && _same(local, base[key]);
      final write =
          key == ReactionsProvider.storageKey ||
          !prefs.containsKey(key) ||
          (base != null && base.containsKey(key) ? unchangedHere : overwrite);
      if (base != null &&
          key != ReactionsProvider.storageKey &&
          (write || _same(local, value))) {
        base[key] = value;
      }
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
    if (account != null && base != null && account == currentUserId) {
      await _saveSettingsBase(prefs, account, base);
    }
    return changed;
  }

  /// Encrypted profile names of this device, in the vault lane format.
  static const profileNamesKey = 'vault_profile_names_v1';

  /// Merges cloud profile names into this device (newest event wins).
  /// Returns true when the stored names changed.
  Future<bool> applyProfileNames(dynamic lane) async {
    final remote = PersonalVault.object(lane);
    if (remote.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    final local = PersonalVault.object(
      jsonDecode(prefs.getString(profileNamesKey) ?? '{}'),
    );
    final merged = PersonalVault.mergeHistory(local, remote);
    if (PersonalVault.canonical(merged) == PersonalVault.canonical(local)) {
      return false;
    }
    await prefs.setString(profileNamesKey, jsonEncode(merged));
    return true;
  }

  /// Merges cloud reactions into this device (newest per title wins).
  /// Returns true when the stored reactions changed.
  Future<bool> applyReactions(dynamic lane) async {
    final remote = PersonalVault.laneToReactions(lane);
    if (remote.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getString(ReactionsProvider.storageKey) ?? '{}';
    final merged = ReactionsProvider.merge(local, jsonEncode(remote));
    if (merged == local) return false;
    await prefs.setString(ReactionsProvider.storageKey, merged);
    return true;
  }

  static String _baseKey(String account) => 'vault_settings_base_$account';

  /// Synced values as they were at the last successful sync of this device:
  /// the common ancestor that tells a local change from a stale value.
  /// Null before the first sync (old behavior applies).
  static Map<String, dynamic>? _settingsBase(
    SharedPreferences prefs,
    String account,
  ) {
    final raw = prefs.getString(_baseKey(account));
    if (raw == null) return null;
    try {
      return PersonalVault.object(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveSettingsBase(
    SharedPreferences prefs,
    String account,
    Map<String, dynamic> base,
  ) async {
    final encoded = jsonEncode(base);
    if (prefs.getString(_baseKey(account)) != encoded) {
      await prefs.setString(_baseKey(account), encoded);
    }
  }

  static bool _same(dynamic a, dynamic b) =>
      PersonalVault.canonical(a) == PersonalVault.canonical(b);

  /// Settings to upload: a key this device left untouched since the last
  /// sync takes the cloud value, so a stale device never reverts a choice
  /// made elsewhere; reactions are unioned instead of replaced.
  @visibleForTesting
  static Map<String, dynamic> resolveSettings({
    required Map<String, dynamic> local,
    required Map<String, dynamic> remote,
    required Map<String, dynamic>? base,
  }) {
    final out = Map<String, dynamic>.from(local);
    for (final e in remote.entries) {
      final mine = local[e.key];
      if (!local.containsKey(e.key) || _same(mine, e.value)) continue;
      if (e.key == ReactionsProvider.storageKey &&
          mine is String &&
          e.value is String) {
        out[e.key] = ReactionsProvider.merge(mine, e.value as String);
      } else if (base != null &&
          base.containsKey(e.key) &&
          _same(mine, base[e.key])) {
        out[e.key] = e.value;
      }
    }
    return out;
  }

  /// Overwrites local storage with cloud credentials (used when the local
  /// device has no playlist configured yet).
  Future<void> applyCredentials(Map<String, dynamic> settings) async {}
  bool hasCredentials(Map<String, dynamic> settings) => false;
  Future<bool> restorePlaylistFromCloud() async => false;

  /// Short reason of the last failed encrypted save, for the settings UI.
  String? lastError;

  Future<void> _cloudWrites = Future<void>.value();
  Future<DateTime?> push(SyncPayload payload, String code) {
    final next = _cloudWrites.then((_) => _push(payload, code));
    _cloudWrites = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return next;
  }

  Future<DateTime?> _push(SyncPayload payload, String code) async {
    if (PlaybackWorkPolicy.instance.blocksCloud) {
      lastError = 'invio rinviato durante la riproduzione';
      return null;
    }
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
      if (code != currentUserId) return null;
      final local = PersonalVault.merge(
        PersonalVault.clean({}),
        payload.toJson(),
      );
      final localSettings = PersonalVault.object(local['settings']);
      final base = _settingsBase(prefs, code);
      Future<DateTime> done() async {
        lastError = null;
        if (code == currentUserId) {
          await _saveSettingsBase(prefs, code, localSettings);
        }
        final now = DateTime.now();
        await prefs.setString(_lastPushKey, now.toIso8601String());
        final collected = payload.collectedAt;
        if (collected != null) {
          await prefs.setString(_lastSnapshotKey, collected.toIso8601String());
        }
        return now;
      }

      for (var attempt = 0; attempt < 4; attempt++) {
        if (PlaybackWorkPolicy.instance.blocksCloud) return null;
        // Fresh revision read is mandatory: the cached copy is reused only
        // when the cloud still holds exactly that revision.
        final read = await _readRemote(code, recovery);
        final remote = read.data;
        final merged = PersonalVault.merge(remote, {
          ...local,
          'settings': resolveSettings(
            local: localSettings,
            remote: PersonalVault.object(remote['settings']),
            base: base,
          ),
        });
        if (code != currentUserId) return null;
        if (read.revision != null &&
            PersonalVault.canonical(remote) ==
                PersonalVault.canonical(merged)) {
          return await done();
        }
        if (PlaybackWorkPolicy.instance.blocksCloud) return null;
        final envelope = await PersonalVault.encrypt(merged, recovery, code);
        if (code != currentUserId || PlaybackWorkPolicy.instance.blocksCloud) {
          return null;
        }
        dynamic revision;
        try {
          revision = await _client.rpc(
            'save_personal_vault',
            params: {
              '_envelope': envelope,
              '_expected_revision': read.revision ?? 0,
            },
          );
        } on PostgrestException catch (e) {
          if (e.code == '40001' && attempt < 3) {
            _remote = null;
            await Future<void>.delayed(
              PlaybackWorkPolicy.conflictDelay(Random()),
            );
            continue;
          }
          rethrow;
        }
        // The RPC stored this envelope at the returned revision (compare and
        // swap). Verify the ciphertext locally instead of downloading it
        // again: AES-GCM authenticates it and the essentials must survive.
        final decoded = await PersonalVault.decrypt(envelope, recovery, code);
        if ((decoded['history'] as Map).length <
            (PersonalVault.clean(merged)['history'] as Map).length) {
          _remote = null;
          throw StateError('Verifica cifrata non riuscita');
        }
        final saved = _revision(revision);
        _remote = saved == null
            ? null
            : _RemoteVault(code, recovery, saved, decoded);
        if (code != currentUserId) return null;
        return await done();
      }
    } catch (e) {
      /* Preserve every local copy on any failure. */
      lastError = e.toString();
      debugPrint('Vault push failed: $e');
      return null;
    }
    lastError = 'conflitto di versione';
    return null;
  }

  /// Reason of the last failed pull, for the settings UI; null on success.
  String? lastPullError;

  /// Reads the cloud copy. Unless [force], a pull whose revision this device
  /// already applied for [profileId] returns `unchanged` after a tiny read,
  /// with no download, decrypt or merge.
  Future<VaultPull> pull(
    String code, {
    String? profileId,
    bool force = false,
  }) async {
    if (PlaybackWorkPolicy.instance.blocksGuide || code != currentUserId) {
      return const VaultPull();
    }
    try {
      final recovery = await recoveryKey();
      if (recovery == null || PlaybackWorkPolicy.instance.blocksGuide) {
        lastPullError = recovery == null
            ? 'chiave di recupero assente su questo dispositivo'
            : null;
        return const VaultPull();
      }
      if (!force) {
        final prefs = await SharedPreferences.getInstance();
        final applied = prefs.getInt(_appliedKey(code, profileId));
        if (applied != null) {
          final head = await _client
              .from('personal_vaults')
              .select('revision')
              .eq('user_id', code)
              .maybeSingle();
          if (head != null && _revision(head['revision']) == applied) {
            lastPullError = null;
            return VaultPull(unchanged: true, revision: applied);
          }
        }
      }
      final read = await _readRemote(
        code,
        recovery,
        headFields: 'revision,updated_at',
      );
      if (PlaybackWorkPolicy.instance.blocksGuide || code != currentUserId) {
        return const VaultPull();
      }
      lastPullError = null;
      if (read.revision == null) return const VaultPull();
      return VaultPull(
        payload: SyncPayload.fromJson(PersonalVault.merge({}, read.data)),
        updatedAt: DateTime.tryParse(read.head?['updated_at'].toString() ?? ''),
        revision: read.revision,
      );
    } catch (e) {
      lastPullError = e.toString();
      debugPrint('Vault pull failed: $e');
      return const VaultPull();
    }
  }

  Future<DateTime?> lastPush() async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(prefs.getString(_lastPushKey) ?? '');
  }

  /// Read time of the newest snapshot confirmed in the encrypted cloud copy:
  /// every local change older than this is safely in the vault.
  Future<DateTime?> lastSavedSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(prefs.getString(_lastSnapshotKey) ?? '');
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

/// Result of [SyncService.pull]. [unchanged] means the cloud still holds
/// the revision this device already applied: nothing to merge.
class VaultPull {
  const VaultPull({
    this.payload,
    this.updatedAt,
    this.revision,
    this.unchanged = false,
  });
  final SyncPayload? payload;
  final DateTime? updatedAt;
  final int? revision;
  final bool unchanged;
}

class _RemoteVault {
  const _RemoteVault(this.account, this.recovery, this.revision, this.data);
  final String account;
  final String recovery;
  final int revision;
  final Map<String, dynamic> data;
}

class _QueuedHistory {
  _QueuedHistory(this.account, this.snapshot);
  String? account;
  Map<String, dynamic> snapshot;
  bool started = false;
  final Completer<void> done = Completer<void>();
}
