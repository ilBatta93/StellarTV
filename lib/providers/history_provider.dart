import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/history_entry.dart';
import '../models/watch_completion_policy.dart';
import '../services/player_settings_service.dart';
import 'app_provider.dart';
import 'sync_provider.dart';
import '../services/sync_service.dart';
import '../services/personal_vault.dart';
import '../services/recent_live_channels.dart';
import '../models/episode_watch_event.dart';

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

  /// Deletion markers (content id -> deletion time). They are saved and
  /// synced with the history so a removed title is not brought back by an
  /// older cloud or device copy; a newer real view wins over the marker.
  final Map<String, DateTime> _deleted = {};
  final Map<String, EpisodeWatchEvent> _watchEvents = {};
  Future<void> _manualWrites = Future<void>.value();
  Future<void>? _loadFuture;

  /// Reloads the app after credentials were restored from the cloud.
  Future<void> Function()? onCredentialsRestored;

  /// Reloads settings-backed state after newer settings arrived.
  Future<void> Function()? onSettingsRestored;

  /// Selected profile: each profile has its own private history.
  String? _profileId;
  int _profileEpoch = 0;
  String? get profileId => _profileId;

  /// Switches to the history of [profileId] (null = no profile selected).
  Future<void> switchProfile(String? profileId, {bool force = false}) async {
    await _manualWrites;
    await _loadFuture;
    if (!force && profileId == _profileId) return;
    _profileEpoch++;
    _pushDebounce?.cancel();
    _profileId = profileId;
    _deleted.clear();
    _watchEvents.clear();
    _entries = [];
    _notify();
    if (profileId != null) await _migrateLegacy(profileId);
    _loadFuture = _loadLocal();
    await _loadFuture;
  }

  /// One time: the history saved before profiles became private goes to the
  /// first profile selected on this device.
  Future<void> _migrateLegacy(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('legacy_history_migrated') == true) return;
    await prefs.setBool('legacy_history_migrated', true);
    final legacy = await _sync.loadLocalHistory();
    if (legacy.isEmpty) return;
    await _sync.mergeHistoryInto(legacy, profileId: profileId);
  }

  List<HistoryEntry> _entries = [];
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  bool _disposed = false;
  Timer? _pushDebounce;

  int _watchedPercent = WatchCompletionPolicy.defaultPercent;
  void setWatchedPercent(int value) {
    final next = WatchCompletionPolicy.normalize(value);
    if (next == _watchedPercent) return;
    _watchedPercent = next;
    _notify();
  }

  HistoryEntry _present(HistoryEntry entry) =>
      entry.copyWith(watchedPercent: _watchedPercent, manualWatched: _eventFor(entry.contentId)?.watched);
  List<HistoryEntry> get entries => _entries.map(_present).toList();
  bool get isLoading => _loading;
  bool get hasLoaded => _loaded;
  String? get error => _error;
  bool get isSyncEnabled => true;

  /// Movies and episodes started but not finished (newest first).
  ///
  /// One item per series: only the most recently watched episode counts.
  /// Older half-watched episodes of the same series are hidden, and when the
  /// latest episode was completed none of the older ones resurfaces.
  List<HistoryEntry> get continueWatching => onePerSeries(entries).where((e) {
    if (e.isLive || e.position < const Duration(seconds: 5)) return false;
    if (e.duration <= Duration.zero) return true;
    return !e.isWatched;
  }).toList();

  /// History with episodes collapsed to the latest one of each series.
  List<HistoryEntry> get entriesOnePerSeries => onePerSeries(entries);

  static final _episodeTag = RegExp(
    r'\bS\d{1,2}\s*E\d{1,4}\b.*$|\b\d{1,2}x\d{1,4}\b.*$',
    caseSensitive: false,
  );

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
      .replaceAll(RegExp(r'^\s*[a-z]{2,3}\s*[:|\-]\s*'), '')
      .replaceAll(RegExp(r'[^a-z0-9à-ÿ]+'), ' ')
      .trim();

  /// Keys identifying the series of an episode entry (empty for others).
  static List<String> seriesKeysOf(HistoryEntry e) {
    if (e.type != ContentType.series && e.type != ContentType.anime) {
      return const [];
    }
    final keys = <String>[];
    if (e.seriesKey.isNotEmpty) keys.add('k:${e.seriesKey}');
    final name = e.seriesName.isNotEmpty
        ? e.seriesName
        : e.title.replaceAll(_episodeTag, '');
    final n = _norm(name);
    if (n.isNotEmpty) keys.add('n:$n');
    return keys;
  }

  /// Keeps entry order (newest first) and drops older episodes of a series
  /// already represented, matching by series key or by series name.
  static List<HistoryEntry> onePerSeries(List<HistoryEntry> entries) {
    final sorted = [...entries]
      ..sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
    final seen = <String>{};
    final out = <HistoryEntry>[];
    for (final e in sorted) {
      final keys = seriesKeysOf(e);
      if (keys.isEmpty) {
        out.add(e);
        continue;
      }
      if (keys.any(seen.contains)) continue;
      seen.addAll(keys);
      out.add(e);
    }
    return out;
  }

  EpisodeWatchEvent? _eventFor(String id, {bool suggestion = false}) =>
      _watchEvents[EpisodeWatchEvent(id, 3, DateTime(2000), suggestion: suggestion).key];
  bool isWatched(String contentId) => _eventFor(contentId)?.watched ?? entryFor(contentId)?.isWatched ?? false;
  bool? manualWatched(String id) => _eventFor(id)?.watched;
  bool suggestionDismissed(String seriesId) => _eventFor(seriesId, suggestion: true)?.value == 2;

  bool _readWatchEvent(Map<String, dynamic> row) {
    if (row['type'] != EpisodeWatchEvent.kind) return false;
    final event = EpisodeWatchEvent.parse(row);
    if (event != null) {
      final previous = _watchEvents[event.key];
      if (previous == null || event.newerThan(previous)) _watchEvents[event.key] = event;
    }
    return true;
  }

  /// A single atomic local batch, no fake progress and no player resume writes.
  Future<void> setManualWatched(Iterable<String> ids, bool? watched, {String? seriesId}) =>
      _writeEvents(ids, watched == null ? 3 : watched ? 1 : 0, seriesId: seriesId);
  Future<void> setSuggestionDismissed(String id, bool dismissed) =>
      _writeEvents([id], dismissed ? 2 : 3, suggestion: true);
  Future<void> _writeEvents(Iterable<String> ids, int value, {bool suggestion = false, String? seriesId}) {
    final targets = ids.where((id) => id.isNotEmpty).toSet();
    final profile = _profileId, epoch = _profileEpoch, account = _sync.currentUserId;
    final next = _manualWrites.then((_) async {
      await _loadFuture;
      if (_disposed || epoch != _profileEpoch || account != _sync.currentUserId) return;
      final before = Map<String, EpisodeWatchEvent>.from(_watchEvents);
      var at = DateTime.now().toUtc();
      for (final id in targets) {
        final previous = _eventFor(id, suggestion: suggestion);
        if (previous != null && !at.isAfter(previous.at)) at = previous.at.add(const Duration(microseconds: 1));
        final event = EpisodeWatchEvent(id, value, at, suggestion: suggestion, seriesId: seriesId ?? previous?.seriesId);
        _watchEvents[event.key] = event;
      }
      final snapshot = _localMap();
      try {
        await _sync.saveLocalHistory(snapshot, profileId: profile);
        if (_disposed || epoch != _profileEpoch || account != _sync.currentUserId) return;
        _notify();
        _scheduleCloudPush();
      } catch (_) {
        if (epoch == _profileEpoch) { _watchEvents..clear()..addAll(before); _notify(); }
        rethrow;
      }
    });
    _manualWrites = next.catchError((Object _) {});
    return next;
  }

  /// Marks an item as fully watched (position = runtime), like Netflix.
  Future<void> markWatched(Channel channel, {Duration? duration}) async {
    await _loadFuture;
    final previous = entryFor(channel.id);
    final event = _eventFor(channel.id);
    if (event != null) {
      final at = DateTime.now().toUtc();
      final reset = EpisodeWatchEvent(channel.id, 3, at.isAfter(event.at) ? at : event.at.add(const Duration(microseconds: 1)));
      _watchEvents[reset.key] = reset;
    }
    var total = previous?.duration ?? Duration.zero;
    if (total <= Duration.zero) total = duration ?? Duration.zero;
    if (total <= Duration.zero) total = const Duration(minutes: 1);
    final entry = HistoryEntry(
      contentId: channel.id,
      type: channel.type,
      title: channel.name,
      posterUrl: channel.logo,
      group: channel.group,
      url: channel.url,
      position: total,
      duration: total,
      lastWatchedAt: DateTime.now(),
      seriesKey: channel.seriesKey ?? previous?.seriesKey ?? '',
      seriesName: channel.seriesName ?? previous?.seriesName ?? '',
      seriesPoster: _seriesPosterFor(channel) ?? previous?.seriesPoster ?? '',
    );
    _entries = [entry, ..._entries.where((e) => e.contentId != channel.id)];
    _notify();
    await _persistLocal();
  }

  /// Clears the watched mark and the resume point.
  Future<void> markUnwatched(String contentId) =>
      remove(contentId, cascade: false);

  /// Poster of the series folder an episode belongs to (not the episode
  /// still), so "Continua a guardare" shows the standard series artwork.
  String? _seriesPosterFor(Channel channel) {
    final key = channel.seriesKey;
    if (key == null || key.isEmpty || channel.isSeriesFolder) return null;
    final folder = _favorites?.seriesFolderFor(key);
    final logo = folder?.logo ?? '';
    return logo.isEmpty ? null : logo;
  }

  HistoryEntry? entryFor(String contentId) {
    for (final e in _entries) {
      if (e.contentId == contentId) return _present(e);
    }
    return null;
  }

  Future<void> _loadLocal() async {
    final local = await _sync.loadLocalHistory(profileId: _profileId);
    final entries = <HistoryEntry>[];
    _deleted.clear();
    _watchEvents.clear();
    for (final value in local.values) {
      if (value is! Map<String, dynamic>) continue;
      if (_readWatchEvent(value)) continue;
      _readTombstone(value);
      final entry = _entryFromLocal(value);
      if (entry != null) entries.add(entry);
    }
    entries.sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
    // Live TV channels are never kept in the history.
    _entries = entries.where((e) => e.type != ContentType.live).toList();
    _loaded = true;
    _notify();
  }

  /// Records a deletion marker; returns true when [map] is one.
  bool _readTombstone(Map<String, dynamic> map) {
    if (map['deleted'] != true) return false;
    final id = map['id'];
    final at = DateTime.tryParse(map['watched']?.toString() ?? '');
    if (id is String && at != null) {
      final known = _deleted[id];
      if (known == null || at.isAfter(known)) _deleted[id] = at;
    }
    return true;
  }

  HistoryEntry? _entryFromLocal(Map<String, dynamic> map) {
    if (map['deleted'] == true) return null;
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
      url:
          _favorites?.channelById(id)?.url ??
          entryFor(id)?.url ??
          map['url'] as String? ??
          '',
      position: Duration(seconds: (map['pos'] as num?)?.toInt() ?? 0),
      duration: Duration(seconds: (map['dur'] as num?)?.toInt() ?? 0),
      lastWatchedAt: watched,
      seriesKey: map['skey'] as String? ?? '',
      seriesName: map['sname'] as String? ?? '',
      seriesPoster: map['sposter'] as String? ?? '',
    );
  }

  Map<String, dynamic> _localMap() {
    // Keep tombstones: a long-offline device must not resurrect removals.
    final live = {for (final e in _entries) e.contentId};
    return {
      for (final event in _watchEvents.values) event.key: event.toJson(),
      for (final d in _deleted.entries)
        if (!live.contains(d.key))
          d.key: {
            'id': d.key,
            'deleted': true,
            'watched': d.value.toIso8601String(),
          },
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
          if (e.seriesKey.isNotEmpty) 'skey': e.seriesKey,
          if (e.seriesName.isNotEmpty) 'sname': e.seriesName,
          if (e.seriesPoster.isNotEmpty) 'sposter': e.seriesPoster,
        },
    };
  }

  Future<void> _persistLocal() async {
    await _sync.saveLocalHistory(_localMap(), profileId: _profileId);
    _scheduleCloudPush();
  }

  void _scheduleCloudPush() {
    _pushDebounce?.cancel();
    _pushDebounce = Timer(Duration.zero, () {
      _syncProvider?.schedulePush();
    });
  }

  /// Pulls cloud state and merges it into local (newer `watched` wins for
  /// history; settings and credentials are filled in when missing locally).
  Future<bool> pullFromCloud() async {
    await _manualWrites;
    // The local load is async and started in the constructor: never merge
    // against an empty in-memory list or this would overwrite the local
    // history with a stale cloud copy on every app start.
    await _loadFuture;
    _loading = true;
    _error = null;
    _notify();
    try {
      final code = await _sync.getStoredCode();
      final epoch = _profileEpoch;
      if (code == null) {
        _error = 'Accedi al tuo account per usare il cloud.';
        return false;
      }
      final (payload, updatedAt) = await _sync.pull(code);
      if (epoch != _profileEpoch || code != _sync.currentUserId) return false;
      if (payload == null) {
        _error = 'Nessun dato salvato nel cloud per questo account.';
        return false;
      }
      // Other profiles' histories are merged straight into local storage.
      for (final e in payload.profileHistories.entries) {
        if (e.key == PersonalVault.favoriteLane ||
            e.key == _profileId ||
            e.value is! Map<String, dynamic>)
          continue;
        await _sync.mergeHistoryInto(
          e.value as Map<String, dynamic>,
          profileId: e.key,
        );
        if (epoch != _profileEpoch || code != _sync.currentUserId) return false;
      }
      if (_profileId == null) {
        await _sync.mergeHistoryInto(payload.history);
      }
      final remoteCurrent = _profileId == null
          ? payload.history
          : (payload.profileHistories[_profileId] as Map<String, dynamic>?) ??
                const <String, dynamic>{};
      final merged = <String, HistoryEntry>{
        for (final e in _entries) e.contentId: e,
      };
      for (final value in remoteCurrent.values) {
        if (value is! Map<String, dynamic>) continue;
        if (_readWatchEvent(value)) continue;
        _readTombstone(value);
      }
      for (final value in remoteCurrent.values) {
        if (value is! Map<String, dynamic>) continue;
        final remote = _entryFromLocal(value);
        if (remote == null) continue;
        final gone = _deleted[remote.contentId];
        if (gone != null && !remote.lastWatchedAt.isAfter(gone)) continue;
        final existing = merged[remote.contentId];
        if (existing == null ||
            remote.lastWatchedAt.isAfter(existing.lastWatchedAt)) {
          merged[remote.contentId] = remote;
        }
      }
      final lastPush = await _sync.lastPush();
      if (epoch != _profileEpoch || code != _sync.currentUserId) return false;
      final cloudIsNewer =
          updatedAt != null &&
          (lastPush == null || updatedAt.isAfter(lastPush.toUtc()));
      _entries =
          merged.values
              .where((e) {
                final gone = _deleted[e.contentId];
                return gone == null || e.lastWatchedAt.isAfter(gone);
              })
              .where((e) => e.type != ContentType.live)
              .toList()
            ..sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
      await _favorites?.applyEncryptedFavorites(payload.toJson());
      // Settings and credentials: fill in what the device does not have yet
      // (never overwrite local values with older cloud copies).
      final settingsChanged = await _sync.applySnapshotSettings(
        payload.settings,
        overwrite: cloudIsNewer,
      );
      if (settingsChanged) await onSettingsRestored?.call();
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
    await _manualWrites;
    _loadFuture = _loadLocal();
    await _loadFuture;
    if (await _sync.getStoredCode() != null) {
      await pullFromCloud();
    }
  }

  /// Pushes the full snapshot now (history + favorites + settings).
  String? get lastPushError => _syncProvider?.lastPushError;

  Future<bool> pushAllNow() async {
    final ok = await _syncProvider?.pushNow() ?? false;
    return ok;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading) {
      // Bring in changes made on other devices, then publish ours.
      _autoPull();
    } else if (state == AppLifecycleState.paused) {
      _syncProvider?.pushNow(silent: true);
    }
  }

  DateTime? _lastAutoPull;
  Timer? _periodic;

  /// Pulls from the cloud when the app comes back to foreground and every
  /// few minutes while open (throttled), so all devices stay aligned.
  Future<void> _autoPull() async {
    final now = DateTime.now();
    if (_lastAutoPull != null &&
        now.difference(_lastAutoPull!) < const Duration(seconds: 45)) {
      return;
    }
    _lastAutoPull = now;
    if (await _sync.getStoredCode() == null) return;
    final ok = await pullFromCloud();
    if (ok) _syncProvider?.schedulePush();
    await onAfterAutoPull?.call();
  }

  /// Called after each automatic pull (e.g. to refresh profiles).
  Future<void> Function()? onAfterAutoPull;

  /// Starts periodic background sync while the app is open.
  void startAutoSync() {
    _periodic?.cancel();
    _periodic = Timer.periodic(const Duration(minutes: 5), (_) => _autoPull());
    _autoPull();
  }

  Future<void> recordStart(Channel channel) async {
    if (channel.type == ContentType.live) return;
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
      seriesKey: channel.seriesKey ?? previous?.seriesKey ?? '',
      seriesName: channel.seriesName ?? previous?.seriesName ?? '',
      seriesPoster: _seriesPosterFor(channel) ?? previous?.seriesPoster ?? '',
    );
    _entries = [entry, ..._entries.where((e) => e.contentId != channel.id)];
    _notify();
    await _persistLocal();
  }

  Future<void> updatePosition(
    String contentId,
    Duration position,
    Duration duration, {
    bool periodic = false,
  }) async {
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
        position: position,
        duration: duration,
        lastWatchedAt: DateTime.now(),
      );
    _notify();
    // Local copy is always immediate. While a video keeps playing the
    // periodic progress tick reaches the cloud at most once per
    // [progressCloudInterval]; pause, exit, app background and every
    // explicit action still sync at once.
    final now = DateTime.now();
    if (periodic && now.difference(_lastProgressPush) < progressCloudInterval) {
      await _sync.saveLocalHistory(_localMap(), profileId: _profileId);
      return;
    }
    _lastProgressPush = now;
    await _persistLocal();
  }

  static const progressCloudInterval = Duration(seconds: 60);
  DateTime _lastProgressPush = DateTime(2000);

  /// Removes a title from the history together with everything tied to it:
  /// for a series episode every episode of that series (watched marks and
  /// positions), plus the player's own resume points for those videos.
  /// [cascade] false touches only [contentId] (used by "segna come non
  /// visto" on a single episode).
  Future<bool> remove(String contentId, {bool cascade = true}) async {
    await _manualWrites;
    await _loadFuture;
    final before = _entries;
    final target = entryFor(contentId);
    final seriesKey = target?.seriesKey ?? '';
    bool related(HistoryEntry e) =>
        e.contentId == contentId ||
        (cascade &&
            seriesKey.isNotEmpty &&
            (e.seriesKey == seriesKey || e.contentId == seriesKey));
    final removed = _entries.where(related).toList();
    final beforeEvents = Map<String, EpisodeWatchEvent>.from(_watchEvents);
    _resetManualStates({contentId, ...removed.map((e) => e.contentId),
      if (cascade) ..._watchEvents.values.where((e) => !e.suggestion && e.seriesId != null && (e.seriesId == contentId || e.seriesId == seriesKey)).map((e) => e.target),
    });
    _entries = _entries.where((e) => !related(e)).toList();
    final now = DateTime.now();
    _deleted[contentId] = now;
    for (final e in removed) {
      _deleted[e.contentId] = now;
    }
    _notify();
    try {
      await _persistLocal();
      final player = PlayerSettingsService();
      for (final e in removed) {
        if (e.url.isNotEmpty) await player.saveResumePosition(e.url, null);
      }
      return true;
    } catch (_) {
      _entries = before;
      _watchEvents..clear()..addAll(beforeEvents);
      _notify();
      return false;
    }
  }

  Future<bool> clear() async {
    await _manualWrites;
    await _loadFuture;
    // "Cancella cronologia" also empties the Diretta recent channels.
    unawaited(RecentLiveChannels.instance.clear());
    final before = _entries;
    final beforeEvents = Map<String, EpisodeWatchEvent>.from(_watchEvents);
    _resetManualStates(_watchEvents.values.where((e) => !e.suggestion).map((e) => e.target).toSet());
    final now = DateTime.now();
    for (final e in _entries) {
      _deleted[e.contentId] = now;
    }
    _entries = [];
    _notify();
    try {
      await _persistLocal();
      await PlayerSettingsService().clearResumePositions();
      return true;
    } catch (_) {
      _entries = before;
      _watchEvents..clear()..addAll(beforeEvents);
      _notify();
      return false;
    }
  }

  void _resetManualStates(Set<String> targets) {
    for (final id in targets) {
      final previous = _eventFor(id);
      if (previous == null) continue;
      final now = DateTime.now().toUtc();
      final event = EpisodeWatchEvent(id, 3, now.isAfter(previous.at) ? now : previous.at.add(const Duration(microseconds: 1)), seriesId: previous.seriesId);
      _watchEvents[event.key] = event;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pushDebounce?.cancel();
    _periodic?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
