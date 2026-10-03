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
  bool _disposed = false;

  /// Set by main.dart: pushes the full snapshot (favorites included).
  Future<SnapshotPart> Function()? snapshotSource;

  String? get code => _code;
  DateTime? get lastPush => _lastPush;
  DateTime? get lastPull => _lastPull;
  bool get isBusy => _busy;
  String? get message => _message;
  bool get success => _success;

  Future<void> load() async {
    _code = await _sync.getStoredCode();
    _lastPush = await _sync.lastPush();
    _lastPull = await _sync.lastPull();
    notifyListeners();
  }

  Future<void> enable() async {
    _busy = true;
    _message = null;
    notifyListeners();
    _code = await _sync.ensureCode();
    // Publish this device's state right away so other devices can pull it.
    await pushNow(silent: true);
    _busy = false;
    _message = 'Sincronizzazione attiva. Usa lo stesso codice sugli altri dispositivi.';
    _success = true;
    notifyListeners();
  }

  Future<void> disable() async {
    _busy = true;
    _message = null;
    notifyListeners();
    _debounce?.cancel();
    await _sync.clearCode();
    _code = null;
    _lastPush = null;
    _lastPull = null;
    _busy = false;
    notifyListeners();
  }

  Future<void> useExistingCode(String code) async {
    final cleaned = code.toUpperCase().trim();
    if (cleaned.length != 8) {
      _message = 'Il codice deve avere 8 caratteri.';
      _success = false;
      notifyListeners();
      return;
    }
    _busy = true;
    _message = null;
    notifyListeners();
    await _sync.setCodeManually(cleaned);
    _code = cleaned;
    final (payload, updated) = await _sync.pull(cleaned);
    if (payload != null) {
      _busy = false;
      _success = true;
      _message =
          'Codice collegato: al prossimo avvio i dati del cloud verranno ripristinati. '
          'Puoi anche scaricarli ora.';
      notifyListeners();
    } else {
      _busy = false;
      _success = updated == null && payload == null;
      _message = updated == null && payload == null
          ? 'Codice impostato, ma nessun dato trovato nel cloud per questo codice.'
          : 'Codice impostato.';
      notifyListeners();
    }
  }

  /// Queues an automatic push (debounced by a few seconds).
  void schedulePush() {
    if (_code == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), () => pushNow(silent: true));
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
          ? 'Nessun dato trovato nel cloud per questo codice.'
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
    _disposed = true;
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
