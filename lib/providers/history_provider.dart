import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/history_entry.dart';
import '../services/settings_service.dart';
import 'app_provider.dart';
import 'sync_provider.dart';
import '../services/sync_service.dart';

/// Local-first watch history: entries are always saved on the device
/// immediately, and mirrored to the cloud sync profile when a pairing code
/// exists. No account required.
class HistoryProvider extends ChangeNotifier with WidgetsBindingObserver {
  HistoryProvider(this._sync, [this._favorites, this._syncProvider]) {
    WidgetsBinding.instance.addObserver(this);
    _loadFuture = _loadLocal();
  }

  final SyncService _sync;
  final AppProvider? _favorites;
  final SyncProvider? _syncProvider;
  final SettingsService _settingsService = SettingsService();
  Future<void>? _loadFuture;

  /// Reloads the app after credentials were restored from the cloud.
  Future<void> Function()? onCredentialsRestored;

  List<HistoryEntry> _entries = [];
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  bool _disposed = false;
  Timer? _pushDebounce;

  List<HistoryEntry> get entries => _entries;
  bool get isLoading => _loading;
  bool get hasLoaded => _loaded;
  String? get error => _error;
  bool get isSyncEnabled => true;

  List<HistoryEntry> get continueWatching =>
      _entries.where((e) => e.resumePosition != null).toList();

  HistoryEntry? entryFor(String contentId) {
    for (final e in _entries) {
      if (e.contentId == contentId) return e;
    }
    return null;
  }

  Future<void> _loadLocal() async {
    final local = await _sync.loadLocalHistory();
    final entries = <HistoryEntry>[];
    for (final value in local.values) {
      if (value is! Map<String, dynamic>) continue;
      final entry = _entryFromLocal(value);
      if (entry != null) entries.add(entry);
    }
    entries.sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
    _entries = entries;
    _loaded = true;
    _notify();
  }

  HistoryEntry? _entryFromLocal(Map<String, dynamic> map) {
    final id = map['id'];
    final title = map['title'];
    if (id is! String || title is! String) return null;
    final watched = DateTime.tryParse(map['watched']?.toString() ?? '');
    if (watched == null) return null;
    return HistoryEntry(
      contentId: id,
      type: ContentType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => ContentType.live,
      ),
      title: title,
      posterUrl: map['poster'] as String? ?? '',
      group: map['group'] as String? ?? '',
      url: map['url'] as String? ?? '',
      position: Duration(seconds: (map['pos'] as num?)?.toInt() ?? 0),
      duration: Duration(seconds: (map['dur'] as num?)?.toInt() ?? 0),
      lastWatchedAt: watched,
    );
  }

  Map<String, dynamic> _localMap() => {
        for (final e in _entries)
          e.contentId: {
            'id': e.contentId,
            'type': e.type.name,
            'title': e.title,
            'poster': e.posterUrl,
            'group': e.group,
            'url': e.url,
            'pos': e.position.inSeconds,
            'dur': e.duration.inSeconds,
            'watched': e.lastWatchedAt.toIso8601String(),
          }
      };

  Future<void> _persistLocal() async {
    await _sync.saveLocalHistory(_localMap());
    _scheduleCloudPush();
  }

  void _scheduleCloudPush() {
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(seconds: 3), () {
      _syncProvider?.schedulePush();
    });
  }

  /// Pulls cloud state and merges it into local (newer `watched` wins for
  /// history; settings and credentials are filled in when missing locally).
  Future<bool> pullFromCloud() async {
    // The local load is async and started in the constructor: never merge
    // against an empty in-memory list or this would overwrite the local
    // history with a stale cloud copy on every app start.
    await _loadFuture;
    _loading = true;
    _error = null;
    _notify();
    try {
      final code = await _sync.getStoredCode();
      if (code == null) {
        _error = 'Nessun codice di sincronizzazione configurato.';
        return false;
      }
      final payload = await _syncProvider?.pullPayload() ??
          (await _sync.pull(code)).$1;
      if (payload == null) {
        _error = 'Nessun dato trovato per il codice $code.';
        return false;
      }
      final merged = <String, HistoryEntry>{
        for (final e in _entries) e.contentId: e,
      };
      for (final value in payload.history.values) {
        if (value is! Map<String, dynamic>) continue;
        final remote = _entryFromLocal(value);
        if (remote == null) continue;
        final existing = merged[remote.contentId];
        if (existing == null ||
            remote.lastWatchedAt.isAfter(existing.lastWatchedAt)) {
          merged[remote.contentId] = remote;
        }
      }
      _entries = merged.values.toList()
        ..sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
      if (_favorites != null && payload.favoriteIds.isNotEmpty) {
        await _favorites.importFavorites({
          'ids': payload.favoriteIds,
          'tmdb': payload.tmdbFavorites,
        });
      }
      // Settings and credentials: fill in what the device does not have yet
      // (never overwrite local values with older cloud copies).
      await _sync.applySnapshotSettings(payload.settings);
      final needsCredentials = await _settingsService.getAuthMethod() == null;
      if (needsCredentials && _sync.hasCredentials(payload.settings)) {
        await _sync.applyCredentials(payload.settings);
        await onCredentialsRestored?.call();
      }
      await _persistLocal();
      await _syncProvider?.markPulled();
      return true;
    } catch (_) {
      _error = 'Sincronizzazione non riuscita. Controlla la connessione.';
      return false;
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Reloads entries from local storage, then pulls any newer state from the
  /// cloud pairing code. Safe to call as a pull-to-refresh handler.
  Future<void> refresh() async {
    await _loadLocal();
    if (await _sync.getStoredCode() != null) {
      await pullFromCloud();
    }
  }

  /// Pushes the full snapshot now (history + favorites + settings).
  Future<bool> pushAllNow() async {
    final ok = await _syncProvider?.pushNow() ?? false;
    return ok;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading) {
      _syncProvider?.schedulePush();
    }
  }

  Future<void> recordStart(Channel channel) async {
    await _loadFuture;
    final now = DateTime.now();
    final previous = entryFor(channel.id);
    final entry = HistoryEntry(
      contentId: channel.id,
      type: channel.type,
      title: channel.name,
      posterUrl: channel.logo,
      group: channel.group,
      url: channel.url,
      position: previous?.position ?? Duration.zero,
      duration: previous?.duration ?? Duration.zero,
      lastWatchedAt: now,
    );
    _entries = [entry, ..._entries.where((e) => e.contentId != channel.id)];
    _notify();
    await _persistLocal();
  }

  Future<void> updatePosition(
      String contentId, Duration position, Duration duration) async {
    if (duration <= Duration.zero) return;
    await _loadFuture;
    final index = _entries.indexWhere((e) => e.contentId == contentId);
    if (index < 0) return;
    final current = _entries[index];
    if (current.position.inSeconds == position.inSeconds &&
        current.duration.inSeconds == duration.inSeconds) {
      return;
    }
    _entries = [..._entries]
      ..[index] = current.copyWith(
          position: position, duration: duration, lastWatchedAt: DateTime.now());
    _notify();
    await _persistLocal();
  }

  Future<bool> remove(String contentId) async {
    final before = _entries;
    _entries = _entries.where((e) => e.contentId != contentId).toList();
    _notify();
    try {
      await _persistLocal();
      return true;
    } catch (_) {
      _entries = before;
      _notify();
      return false;
    }
  }

  Future<bool> clear() async {
    final before = _entries;
    _entries = [];
    _notify();
    try {
      await _persistLocal();
      return true;
    } catch (_) {
      _entries = before;
      _notify();
      return false;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pushDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
