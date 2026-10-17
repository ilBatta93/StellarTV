import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/sync_service.dart';

/// Exposes the pairing-code sync to the settings UI: status, code display,
/// manual code entry, push and pull. When a code is set, every local change
/// is pushed to the cloud automatically (debounced).
class SyncProvider extends ChangeNotifier {
  SyncProvider(this._sync);

  final SyncService _sync;

  String? _code;
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

  String? get email => _sync.currentEmail;
  bool get isSignedIn => _sync.currentUserId != null;

  /// Bounded wait for the saved session on cold start (see SyncService).
  Future<bool> waitForSession() async {
    final ok = await _sync.waitForSession();
    if (ok) await load();
    return ok;
  }

  Future<void> load() async {
    _code = await _sync.getStoredCode();
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
      _code = await _sync.getStoredCode();
      if (_code != null) await onCodeReady?.call(_code!);
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
    await _sync.signOut();
    _code = null;
    _lastPush = null;
    _lastPull = null;
    await onCodeCleared?.call();
    _busy = false;
    notifyListeners();
  }

  /// Queues an automatic push (debounced by a few seconds).
  void schedulePush() {
    if (_code == null) return;
    _debounce?.cancel();
    // Instant: Duration.zero only coalesces changes from the same frame.
    _debounce = Timer(Duration.zero, _autoPush);
  }

  bool _autoPushing = false;
  bool _autoPending = false;

  /// One automatic push at a time; a change during it triggers exactly one
  /// follow-up push, so nothing is lost and requests never overlap.
  Future<void> _autoPush() async {
    if (_autoPushing) {
      _autoPending = true;
      return;
    }
    _autoPushing = true;
    try {
      do {
        _autoPending = false;
        await pushNow(silent: true);
      } while (_autoPending);
    } finally {
      _autoPushing = false;
    }
  }

  Future<bool> pushNow({bool silent = false}) async {
    final code = _code;
    if (code == null) return false;
    if (!silent) {
      _busy = true;
      _message = null;
      notifyListeners();
    }
    try {
      final part = await snapshotSource?.call() ??
          (const SnapshotPart(history: {}, favoriteIds: [], tmdbFavorites: []));
      final payload = await _sync.collectSnapshot(
        favoriteIds: part.favoriteIds,
        tmdbFavorites: part.tmdbFavorites,
      );
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
        _message = 'Invio non riuscito. Controlla la connessione.';
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
    _debounce?.cancel();
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

