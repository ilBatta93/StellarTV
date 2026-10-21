import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/sync_service.dart';
import '../services/playback_work_policy.dart';

/// Exposes the pairing-code sync to the settings UI: status, code display,
/// manual code entry, push and pull. When a code is set, every local change
/// is pushed to the cloud automatically (debounced).
class SyncProvider extends ChangeNotifier {
  SyncProvider(this._sync) {
    PlaybackWorkPolicy.instance.addListener(_onPlaybackChanged);
  }

  void _onPlaybackChanged() {
    if (PlaybackWorkPolicy.instance.blocksCloud) {
      if (_debounce != null || _retryTimer != null) _autoPending = true;
      _debounce?.cancel();
      _debounce = null;
      _retryTimer?.cancel();
      _retryTimer = null;
      return;
    }
    if (_autoPending) {
      schedulePush();
    }
  }

  final SyncService _sync;

  /// Cloud data always belong to the signed-in account. Reading it live
  /// (instead of caching it at password sign-in) keeps sync working after a
  /// QR/TV pairing sign-in or a restored session, where the cache stayed
  /// empty and every upload silently stopped while downloads still worked.
  String? get _code => _sync.currentUserId;
  DateTime? _lastPush;
  DateTime? _lastPull;
  bool _busy = false;
  String? _message;
  bool _success = false;
  Timer? _debounce;

  /// Set by main.dart: pushes the full snapshot (favorites included).
  Future<SnapshotPart> Function()? snapshotSource;

  /// Set by main.dart: uploads every local favorite when a code is enabled or
  /// entered, so the cloud starts from the list already on the device.
  Future<void> Function(String code)? onCodeReady;

  /// Set by main.dart: stops mirroring favorites to the cloud when sync is
  /// turned off (local favorites are kept).
  Future<void> Function()? onCodeCleared;

  String? get code => _code;
  DateTime? get lastPush => _lastPush;
  DateTime? get lastPull => _lastPull;
  bool get isBusy => _busy;
  String? get message => _message;
  bool get success => _success;

  Future<String?> recoveryKey() => _sync.recoveryKey();
  Future<bool> hasCloudVault() => _sync.hasCloudVault();
  Future<void> authorizeVault(String recovery) =>
      _sync.authorizeVault(recovery);
  String? get lastPushError => _sync.lastError;
  Future<void> forgetVaultKey() => _sync.forgetVaultKey();

  String? get email => _sync.currentEmail;
  bool get isSignedIn => _sync.currentUserId != null;

  /// Bounded wait for the saved session on cold start (see SyncService).
  Future<bool> waitForSession() async {
    final ok = await _sync.waitForSession();
    if (ok) await load();
    return ok;
  }

  Future<void> load() async {
    await _sync.getStoredCode();
    _lastPush = await _sync.lastPush();
    _lastPull = await _sync.lastPull();
    notifyListeners();
  }

  /// Returns null on success, otherwise an Italian error message.
  Future<String?> signIn(String email, String password) =>
      _auth(() => _sync.signIn(email, password));

  Future<String?> signUp(String email, String password) =>
      _auth(() => _sync.signUp(email, password));

  Future<String?> resetPassword(String email) => _sync.resetPassword(email);

  Future<String?> resendConfirmation(String email) =>
      _sync.resendConfirmation(email);

  /// Restores the Xtream list saved on the website when this device has none.
  Future<bool> restorePlaylistFromCloud() => _sync.restorePlaylistFromCloud();

  Future<String?> _auth(Future<String?> Function() action) async {
    _busy = true;
    _message = null;
    notifyListeners();
    final error = await action();
    if (error == null) {
      final code = await _sync.getStoredCode();
      if (code != null) await onCodeReady?.call(code);
    }
    _busy = false;
    notifyListeners();
    return error;
  }

  /// Signs out: stops syncing and clears this device.
  Future<void> signOut() async {
    _busy = true;
    notifyListeners();
    _debounce?.cancel();
    _retryTimer?.cancel();
    _retryTimer = null;
    _failures = 0;
    _retryAt = null;
    _autoPending = false;
    await _sync.signOut();
    _lastPush = null;
    _lastPull = null;
    await onCodeCleared?.call();
    _busy = false;
    notifyListeners();
  }

  /// Queues an automatic push (debounced by a few seconds).
  void schedulePush() {
    if (_code == null) return;
    if (PlaybackWorkPolicy.instance.blocksCloud) {
      _autoPending = true;
      return;
    }
    final retryAt = _retryAt;
    if (retryAt != null && retryAt.isAfter(DateTime.now())) {
      _autoPending = true;
      _retryTimer ??= Timer(retryAt.difference(DateTime.now()), () {
        _retryTimer = null;
        _autoPush();
      });
      return;
    }
    // After a failed save the next attempt is already scheduled: the change
    // is kept locally and included then, instead of hammering the cloud.
    if (_retryTimer != null) {
      _autoPending = true;
      return;
    }
    _debounce?.cancel();
    // Instant: Duration.zero only coalesces changes from the same frame.
    _debounce = Timer(Duration.zero, _autoPush);
  }

  bool _autoPushing = false;
  bool _autoPending = false;
  int _failures = 0;
  Timer? _retryTimer;
  DateTime? _retryAt;

  /// Successful saves stay instant; only consecutive failures back off
  /// (5 s, 10 s, 20 s ... capped at 10 minutes).
  static Duration retryDelay(int failures) {
    final seconds = 5 * (1 << (failures - 1).clamp(0, 7));
    return Duration(seconds: seconds > 600 ? 600 : seconds);
  }

  /// One automatic push at a time; a change during it triggers exactly one
  /// follow-up push, so nothing is lost and requests never overlap.
  Future<void> _autoPush() async {
    _debounce = null;
    if (PlaybackWorkPolicy.instance.blocksCloud) {
      _autoPending = true;
      return;
    }
    if (_autoPushing) {
      _autoPending = true;
      return;
    }
    _autoPushing = true;
    try {
      do {
        _autoPending = false;
        final ok = await pushNow(silent: true);
        if (!ok) {
          if (PlaybackWorkPolicy.instance.blocksCloud) {
            _autoPending = true;
            break;
          }
          _failures++;
          _autoPending = false;
          _retryTimer?.cancel();
          final delay = retryDelay(_failures);
          _retryAt = DateTime.now().add(delay);
          _retryTimer = Timer(delay, () {
            _retryTimer = null;
            _autoPush();
          });
          break;
        }
        _failures = 0;
        _retryAt = null;
      } while (_autoPending && !PlaybackWorkPolicy.instance.blocksCloud);
    } finally {
      _autoPushing = false;
    }
  }

  Future<bool> pushNow({bool silent = false}) async {
    final code = _code;
    if (code == null) return false;
    if (PlaybackWorkPolicy.instance.blocksCloud) {
      _autoPending = true;
      return false;
    }
    if (!silent) {
      _busy = true;
      _message = null;
      notifyListeners();
    }
    try {
      final part =
          await snapshotSource?.call() ??
          (const SnapshotPart(history: {}, favoriteIds: [], tmdbFavorites: []));
      final payload = await _sync.collectSnapshot(
        favoriteIds: part.favoriteIds,
        tmdbFavorites: part.tmdbFavorites,
      );
      if (PlaybackWorkPolicy.instance.blocksCloud) {
        _autoPending = true;
        return false;
      }
      final ok = await _sync.push(payload, code);
      if (ok != null) {
        _lastPush = ok;
        if (!silent) {
          _success = true;
          _message = 'Dati inviati al cloud.';
        }
        return true;
      }
      if (!silent) {
        _success = false;
        final why = _sync.lastError;
        _message =
            'Invio non riuscito. Verifica connessione e chiave in Dati cifrati.'
            '${why == null ? '' : ' (dettaglio: ${why.length > 120 ? why.substring(0, 120) : why})'}';
      }
      return false;
    } finally {
      if (!silent) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  /// Pulls the cloud snapshot, applies it via [HistoryProvider.pullFromCloud]
  /// and marks the pull so the settings screen can show progress.
  Future<bool> pullNow() async {
    final code = _code;
    if (code == null) return false;
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      final (payload, _) = await _sync.pull(code);
      _success = payload != null;
      _message = payload == null
          ? 'Nessun dato salvato nel cloud per questo account.'
          : 'Dati scaricati dal cloud.';
      return payload != null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Pulls the cloud snapshot and returns it; does not apply anything.
  Future<SyncPayload?> pullPayload() async {
    final code = _code;
    if (code == null) return null;
    final (payload, _) = await _sync.pull(code);
    return payload;
  }

  Future<void> markPulled() async {
    await _sync.markPulled();
    _lastPull = DateTime.now();
    notifyListeners();
  }

  void clearMessage() {
    if (_message == null) return;
    _message = null;
    notifyListeners();
  }

  @override
  void dispose() {
    PlaybackWorkPolicy.instance.removeListener(_onPlaybackChanged);
    _debounce?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }
}

/// The pieces of the snapshot that live outside SharedPreferences.
class SnapshotPart {
  final Map<String, dynamic> history;
  final List<String> favoriteIds;
  final List<Map<String, dynamic>> tmdbFavorites;

  const SnapshotPart({
    required this.history,
    required this.favoriteIds,
    required this.tmdbFavorites,
  });
}
