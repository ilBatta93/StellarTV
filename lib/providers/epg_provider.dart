import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/epg_program.dart';
import '../services/epg_archive.dart';
import '../services/epg_channel_match.dart';
import '../services/epg_prefix_index.dart';
import '../services/epg_service.dart';
import '../services/epg_short.dart';
import '../services/epg_timeline.dart';
import '../services/playback_work_policy.dart';
import '../services/frame_telemetry_service.dart';
import 'app_provider.dart';

/// TV guide for the live channels. The playlist guide (Xtream xmltv.php) is
/// used automatically; extra XMLTV sources can be added in Settings. The
/// guide refreshes on its own (every 12 hours by default).
class EpgProvider extends ChangeNotifier {
  EpgProvider(this._app) {
    _app.addListener(_onAppChanged);
    PlaybackWorkPolicy.instance.addListener(_onPlaybackChanged);
    _start();
  }

  final AppProvider _app;
  final EpgService _service = EpgService();
  Timer? _timer;
  bool _deferred = false;
  bool _disposed = false;
  bool _ready = false;
  bool get _playbackBlocked =>
      _app.isLoading ||
      _app.playbackActive ||
      PlaybackWorkPolicy.instance.blocksGuide;

  bool _wasBlocked = false;
  void _onPlaybackChanged() {
    final resumed = _wasBlocked && !_playbackBlocked;
    _wasBlocked = _playbackBlocked;
    if (_playbackBlocked) {
      if (_loading) {
        _deferred = true;
        _service.deferActiveDownload();
      }
      _timer?.cancel();
      return;
    }
    if (_deferred && !_playbackBlocked && !_disposed) {
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 20), refresh);
    } else if (resumed && !_disposed && _ready) {
      _schedule();
    }
  }

  EpgData _data = const EpgData();
  EpgArchive? _archive;
  EpgPrefixIndex? _prefix;
  Map<String, List<String>>? _catalogIdsByGuide;
  int _searchRevision = 0;
  int _prefixToken = 0;
  int _boundCatalog = -1;
  int? _bindingRevision;
  final Map<String, List<EpgProgram>> _short = {};
  final Set<String> _shortEmpty = {};
  final Map<String, List<EpgTimelineSlot>> _shortSlots = {};
  final Map<String, _TrimmedTimeline> _shortTrimmed = {};
  final Set<String> _shortTried = {};
  final Set<String> _shortQueued = {};
  final List<Channel> _shortQueue = [];
  var _shortActive = 0;
  bool _loading = false;
  String? _error;
  bool _usePlaylist = true;
  List<String> _manual = const [];
  int _intervalMinutes = 1440;
  DateTime? _lastRun;
  String? _scheduledFor;
  String? _cacheSource;
  int _cacheEpoch = 0;
  int _playlistRefreshRevision = 0;
  EpgMatcher? _nameIndex;
  final Map<String, EpgMatch?> _channelMatch = {};
  final Map<EpgMatch, List<EpgProgram>> _gridLists = {};
  final Map<EpgMatch, List<EpgTimelineSlot>> _timelines = {};
  final Map<EpgMatch, _TrimmedTimeline> _trimmed = {};
  DateTime? _gridFrom;
  DateTime? _gridTo;

  bool get isLoading => _loading;
  bool get isReady => _ready;
  bool get refreshDeferred => _deferred;
  String? get error => _error;
  bool get hasData => !_data.isEmpty;
  bool get hasListings =>
      programmeCount > 0 || _short.values.any((list) => list.isNotEmpty);
  bool get degraded => _data.degraded;
  int get searchRevision => _searchRevision;
  bool get usePlaylistGuide => _usePlaylist;
  List<String> get manualSources => _manual;
  int get intervalMinutes => _intervalMinutes;
  DateTime? get lastUpdate => _data.fetchedAt ?? _lastRun;
  int get programmeCount => _data.programmeCount;
  int get channelCount => _data.guideIds.length;

  /// XMLTV address provided by the Xtream account, when logged in.
  String? get playlistSource {
    final c = _app.xtreamCredentials;
    if (_app.authMethod != AuthMethod.xtream || c == null) return null;
    var base = c['server']!.trim();
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      base = 'http://$base';
    }
    base = base.replaceAll(RegExp(r'/+$'), '');
    return '$base/xmltv.php?username=${Uri.encodeComponent(c['username']!)}'
        '&password=${Uri.encodeComponent(c['password']!)}';
  }

  List<String> get _activeSources => [
    if (_usePlaylist && playlistSource != null) playlistSource!,
    ..._manual,
  ];

  Future<void> _start() async {
    _usePlaylist = await _service.usePlaylistGuide();
    _manual = await _service.manualSources();
    _intervalMinutes = await _service.intervalMinutes();
    _lastRun = await _service.lastRun();
    if (_disposed) return;
    await _loadCachedGuide();
    if (_disposed) return;
    _schedule();
  }

  Future<void> _loadCachedGuide() async {
    final sources = _activeSources;
    final cached = await _service.loadCache(sources);
    if (_disposed) return;
    _cacheSource = sources.join('|');
    _lastRun = cached.fetchedAt;
    _playlistRefreshRevision = _app.playlistRefreshRevision;
    _ready = true;
    _adopt(cached);
    notifyListeners();
  }

  void _onAppChanged() {
    if (!_ready || _disposed) return;
    _onPlaybackChanged();
    // Credentials can arrive after startup (login or cloud restore).
    final signature = _activeSources.join('|');
    if (signature != _cacheSource) {
      _timer?.cancel();
      _cacheSource = signature;
      _adopt(EpgGuideSnapshot.empty);
      _service.deferActiveDownload();
      unawaited(_restoreSourceCache());
    } else if (signature != _scheduledFor) {
      _schedule();
    }
    if (_playlistRefreshRevision != _app.playlistRefreshRevision) {
      _playlistRefreshRevision = _app.playlistRefreshRevision;
      _deferred = true;
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 20), refresh);
    }
    _channelMatch.clear();
    if (_archive != null) unawaited(_bindCatalog(_prefixToken));
  }

  Future<void> _restoreSourceCache() async {
    final epoch = ++_cacheEpoch;
    final sources = _activeSources;
    final applied = await _applyCache(sources, epoch);
    if (applied && !_disposed) _schedule();
  }

  Future<bool> _applyCache(List<String> sources, int epoch) async {
    final data = await _service.loadCache(sources);
    if (_disposed ||
        epoch != _cacheEpoch ||
        sources.join('|') != _cacheSource) {
      return false;
    }
    _lastRun = data.fetchedAt;
    _adopt(data);
    notifyListeners();
    return true;
  }

  void _adopt(EpgGuideSnapshot snapshot) {
    _archive?.close();
    _archive = snapshot.archive;
    _prefix = null;
    _catalogIdsByGuide = null;
    _boundCatalog = -1;
    _prefixToken++;
    _short.clear();
    _shortEmpty.clear();
    _shortSlots.clear();
    _shortTrimmed.clear();
    _shortTried.clear();
    _shortQueued.clear();
    _shortQueue.clear();
    _setData(snapshot.data);
    final token = _prefixToken;
    final archive = snapshot.archive;
    if (archive != null) {
      unawaited(_loadPrefix(archive, token));
      unawaited(_bindCatalog(token));
    } else {
      _searchRevision++;
    }
  }

  Future<void> _loadPrefix(EpgArchive archive, int token) async {
    final index = await archive.loadPrefix();
    if (_disposed || token != _prefixToken || !identical(archive, _archive))
      return;
    _prefix = index;
    _searchRevision++;
    notifyListeners();
  }

  Future<void> _bindCatalog(int token) async {
    final revision = _app.catalogIndexRevision;
    if (_bindingRevision == revision) return;
    if (_boundCatalog == revision && _catalogIdsByGuide != null) return;
    _bindingRevision = revision;
    try {
      final rows = await _app.liveIdentities();
      if (_disposed || token != _prefixToken) return;
      final ids = _data.guideIds;
      final names = _data.displayNames;
      final reverse = rows.isEmpty || ids.isEmpty
          ? <String, List<String>>{}
          : await Isolate.run(() => epgCatalogIdsByGuide(ids, names, rows));
      if (_disposed ||
          token != _prefixToken ||
          revision != _app.catalogIndexRevision) {
        return;
      }
      _catalogIdsByGuide = reverse;
      _boundCatalog = revision;
      _searchRevision++;
      notifyListeners();
    } catch (_) {
      return;
    } finally {
      if (_bindingRevision == revision) _bindingRevision = null;
    }
  }

  void _setData(EpgData data) {
    final now = DateTime.now();
    _data = _archive == null ? epgDataInGuideWindow(data, now) : data;
    _nameIndex = null;
    _channelMatch.clear();
    _gridLists.clear();
    _timelines.clear();
    _trimmed.clear();
    _gridFrom = epgGridOrigin(now);
    _gridTo = now.add(epgGuideFuture);
  }

  /// Drops programmes that have left the grid horizon. Descriptions already
  /// omitted stay omitted. Skipped while a playback session owns the device.
  bool rollGuideWindow() {
    if (_playbackBlocked || _disposed || !_ready) return false;
    final now = DateTime.now();
    final from = epgGridOrigin(now);
    if (_gridFrom == from) return false;
    final next = epgDataInGuideWindow(_data, now);
    _gridFrom = from;
    _gridTo = now.add(epgGuideFuture);
    _gridLists.clear();
    _timelines.clear();
    _trimmed.clear();
    _shortSlots.clear();
    _shortTrimmed.clear();
    if (_archive != null) {
      notifyListeners();
      return true;
    }
    if (identical(next, _data)) return false;
    _data = next;
    _nameIndex = null;
    _channelMatch.clear();
    notifyListeners();
    return true;
  }

  void _schedule() {
    _timer?.cancel();
    _scheduledFor = _activeSources.join('|');
    if (_activeSources.isEmpty) return;
    final due = epgGuideNeedsRefresh(
      empty: _data.isEmpty,
      programmeCount: _data.programmeCount,
      hasChannels: _data.channelIndex.isNotEmpty,
      lastRun: _lastRun,
      intervalMinutes: _intervalMinutes,
      now: DateTime.now(),
    );
    if (_playbackBlocked) {
      // Retain due work even when the first scheduling attempt happens while
      // a preview is active. Closing that session must resume the download.
      if (due && !_deferred) {
        _deferred = true;
        notifyListeners();
      }
      return;
    }
    if (due) {
      refresh();
    } else if (_intervalMinutes > 0) {
      final wait =
          Duration(minutes: _intervalMinutes) -
          DateTime.now().difference(_lastRun!);
      _timer = Timer(wait, refresh);
    }
  }

  /// Downloads the guide now.
  Future<void> refresh() async {
    if (_disposed || !_ready) return;
    if (_loading) {
      _deferred = true;
      return;
    }
    if (_playbackBlocked) {
      _deferred = true;
      _timer?.cancel();
      notifyListeners();
      return;
    }
    _deferred = false;
    final sources = _activeSources;
    if (sources.isEmpty) {
      _error = 'Nessuna fonte EPG: attiva la guida della playlist o aggiungi un indirizzo.';
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      FrameTelemetryService.instance.mark('guida: download avviato');
      final previousCount = _data.programmeCount;
      final data = await _service.fetch(sources);
      if (_disposed) {
        await _service.discard(data);
        return;
      }
      if (_playbackBlocked || sources.join('|') != _activeSources.join('|')) {
        await _service.discard(data);
        throw EpgRefreshDeferred();
      }
      if (!epgGuideIsFresh(data.programmeCount)) {
        if (epgKeepsPreviousGuide(
          previousCount: previousCount,
          incomingCount: data.programmeCount,
        )) {
          await _service.discard(data);
        } else {
          final previous = _archive;
          _archive = null;
          previous?.close();
          await _service.publish(data, sources);
          _adopt(data);
        }
        FrameTelemetryService.instance.mark('guida: senza programmi');
        _deferred = true;
        return;
      }
      final previous = _archive;
      _archive = null;
      previous?.close();
      await _service.publish(data, sources);
      _adopt(data);
      FrameTelemetryService.instance.mark('guida: pronta');
      await _service.markRun();
      _lastRun = DateTime.now();
    } on EpgRefreshDeferred {
      FrameTelemetryService.instance.mark('guida: rinviata');
      _deferred = true;
    } on EpgDownloadException catch (e) {
      FrameTelemetryService.instance.mark('guida: errore download');
      _error = e.message;
    } catch (_) {
      _error = 'Impossibile leggere la guida TV. Riprova.';
    } finally {
      _loading = false;
      if (!_disposed) notifyListeners();
      _timer?.cancel();
      if (!_disposed && _playbackBlocked) {
        _deferred = true;
      } else if (!_disposed && _deferred) {
        _timer = Timer(const Duration(seconds: 20), refresh);
      } else if (!_disposed && _intervalMinutes > 0) {
        _timer = Timer(Duration(minutes: _intervalMinutes), refresh);
      }
    }
  }

  Future<void> setUsePlaylistGuide(bool value) async {
    _usePlaylist = value;
    await _service.setUsePlaylistGuide(value);
    notifyListeners();
    await refresh();
  }

  Future<void> addSource(String url) async {
    final clean = url.trim();
    if (clean.isEmpty || _manual.contains(clean)) return;
    _manual = [..._manual, clean];
    await _service.saveManualSources(_manual);
    notifyListeners();
    await refresh();
  }

  Future<void> removeSource(String url) async {
    _manual = _manual.where((u) => u != url).toList();
    await _service.saveManualSources(_manual);
    notifyListeners();
    await refresh();
  }

  Future<void> setIntervalMinutes(int minutes) async {
    _intervalMinutes = minutes;
    await _service.saveIntervalMinutes(minutes);
    notifyListeners();
    _schedule();
  }

  /// Guide match for a playlist channel, keeping "+1" channels separate.
  EpgMatch? _guideIdFor(Channel channel) {
    if (_channelMatch.containsKey(channel.id)) return _channelMatch[channel.id];
    final matcher = _nameIndex ??= EpgMatcher(
      guideIds: _data.guideIds.toSet(),
      displayNames: _data.displayNames,
    );
    final match = matcher.match(
      name: channel.name,
      tvgName: channel.tvgName,
      tvgId: channel.tvgId,
    );
    _channelMatch[channel.id] = match;
    return match;
  }

  String? guideIdFor(Channel channel) => _guideIdFor(channel)?.id;

  Set<String> guideIdsMatching(String query) {
    final prefix = _prefix;
    if (prefix == null) return const {};
    final ids = _data.guideIds;
    final out = <String>{};
    for (final ordinal in prefix.ordinals(query)) {
      if (ordinal >= 0 && ordinal < ids.length) out.add(ids[ordinal]);
    }
    return out;
  }

  /// Catalog ids whose guide channel matches [query]. Empty until the prefix
  /// index and the channel map have been built off the UI isolate.
  List<String> catalogIdsForProgrammeQuery(String query) {
    final prefix = _prefix;
    final reverse = _catalogIdsByGuide;
    if (prefix == null || reverse == null || query.trim().length < 2)
      return const [];
    final ids = _data.guideIds;
    final out = <String>[];
    final seen = <String>{};
    for (final ordinal in prefix.ordinals(query)) {
      if (ordinal < 0 || ordinal >= ids.length) continue;
      for (final id in reverse[ids[ordinal]] ?? const <String>[]) {
        if (seen.add(id)) out.add(id);
        if (out.length >= 40) return out;
      }
    }
    return out;
  }

  List<EpgProgram> programmesFor(Channel channel) =>
      _programmes(channel, synopsis: false);

  /// Programme sheet: same window as the grid, with the synopsis kept on disk
  /// until the row is opened.
  List<EpgProgram> listingsFor(Channel channel) =>
      _programmes(channel, synopsis: true);

  List<EpgProgram> _programmes(Channel channel, {required bool synopsis}) {
    final match = _guideIdFor(channel);
    if (match != null) {
      final full = _windowed(_readGuide(match.id), match);
      if (full.isNotEmpty) {
        if (synopsis) return full;
        return _gridLists[match] ??= _titlesOnly(full);
      }
    }
    if (_short.containsKey(channel.id)) return _short[channel.id] ?? const [];
    _requestShort(channel);
    return const [];
  }

  List<EpgProgram> _readGuide(String id) {
    final archive = _archive;
    if (archive != null) return archive.read(id);
    return _data.programmes[id] ?? const <EpgProgram>[];
  }

  List<EpgProgram> _windowed(List<EpgProgram> source, EpgMatch match) {
    if (source.isEmpty) return const [];
    final from = _gridFrom ?? epgGridOrigin(DateTime.now());
    final to = _gridTo ?? DateTime.now().add(epgGuideFuture);
    if (match.shiftHours == 0) return epgSliceGuide(source, from, to);
    final shift = Duration(hours: match.shiftHours);
    return epgSliceGuide(
      [
        for (final program in source)
          if (program.endTime.isAfter(program.startTime))
            EpgProgram(
              id: '${program.id}+${match.shiftHours}',
              channelId: program.channelId,
              title: program.title,
              description: program.description,
              startTime: program.startTime.add(shift),
              endTime: program.endTime.add(shift),
            ),
      ],
      from,
      to,
    );
  }

  List<EpgProgram> _titlesOnly(List<EpgProgram> source) {
    var clean = true;
    for (final program in source) {
      if (program.description.isNotEmpty) {
        clean = false;
        break;
      }
    }
    if (clean) return source;
    return List.unmodifiable([
      for (final program in source)
        program.description.isEmpty
            ? program
            : EpgProgram(
                id: program.id,
                channelId: program.channelId,
                title: program.title,
                description: '',
                startTime: program.startTime,
                endTime: program.endTime,
              ),
    ]);
  }

  /// An empty short listing is not final. Focusing the row again may retry it.
  void reopenShort(Channel channel) {
    if (!_shortEmpty.remove(channel.id)) return;
    _shortTried.remove(channel.id);
    _short.remove(channel.id);
  }

  void _requestShort(Channel channel) {
    if (_disposed || channel.type != ContentType.live) return;
    if (_short.containsKey(channel.id) || _shortTried.contains(channel.id))
      return;
    if (_shortQueued.contains(channel.id)) return;
    if (epgStreamId(channel.id) == null) {
      _shortTried.add(channel.id);
      return;
    }
    final credentials = _app.xtreamCredentials;
    if (_app.authMethod != AuthMethod.xtream || credentials == null) return;
    if (_shortQueued.length + _shortActive >= 24) return;
    _shortQueued.add(channel.id);
    _shortQueue.add(channel);
    _kickShort();
  }

  void _kickShort() {
    while (_shortActive < 3 && _shortQueue.isNotEmpty && !_disposed) {
      final channel = _shortQueue.removeAt(0);
      _shortQueued.remove(channel.id);
      if (!_shortTried.add(channel.id)) continue;
      _shortActive++;
      unawaited(
        _fetchShort(channel).whenComplete(() {
          _shortActive--;
          if (!_disposed) _kickShort();
        }),
      );
    }
  }

  Future<void> _fetchShort(Channel channel) async {
    final streamId = epgStreamId(channel.id);
    final credentials = _app.xtreamCredentials;
    if (streamId == null || credentials == null) return;
    final list = await EpgShortGuide.fetch(
      server: credentials['server'] ?? '',
      username: credentials['username'] ?? '',
      password: credentials['password'] ?? '',
      streamId: streamId,
    );
    if (_disposed) return;
    if (list.isEmpty) {
      _shortEmpty.add(channel.id);
      return;
    }
    _shortEmpty.remove(channel.id);
    _short[channel.id] = list;
    final match = _channelMatch[channel.id];
    if (match != null) {
      _timelines.remove(match);
      _trimmed.remove(match);
      _gridLists.remove(match);
    }
    _shortSlots.remove(channel.id);
    _shortTrimmed.remove(channel.id);
    notifyListeners();
  }

  /// Slots for [channel], built once per guide snapshot. [notBefore] only
  /// hides rows the grid cannot scroll to; it does not sort again.
  List<EpgTimelineSlot> timelineFor(Channel channel, {DateTime? notBefore}) {
    final programmes = programmesFor(channel);
    if (programmes.isEmpty) return const [];
    final match = _guideIdFor(channel);
    final fromGuide = match != null && _gridLists.containsKey(match);
    final slots = fromGuide
        ? (_timelines[match] ??= epgTimelineSlots(programmes))
        : (_shortSlots[channel.id] ??= epgTimelineSlots(programmes));
    if (notBefore == null) return slots;
    if (fromGuide) {
      final cached = _trimmed[match];
      if (cached != null && cached.origin == notBefore) return cached.slots;
      final trimmed = _trim(slots, notBefore);
      _trimmed[match] = _TrimmedTimeline(notBefore, trimmed);
      return trimmed;
    }
    final cached = _shortTrimmed[channel.id];
    if (cached != null && cached.origin == notBefore) return cached.slots;
    final trimmed = _trim(slots, notBefore);
    _shortTrimmed[channel.id] = _TrimmedTimeline(notBefore, trimmed);
    return trimmed;
  }

  List<EpgTimelineSlot> _trim(
    List<EpgTimelineSlot> slots,
    DateTime notBefore,
  ) => List<EpgTimelineSlot>.unmodifiable([
    for (final slot in slots)
      if (slot.end.isAfter(notBefore)) slot,
  ]);

  EpgProgram? nowFor(Channel channel) {
    final now = DateTime.now();
    for (final program in programmesFor(channel)) {
      if (!program.startTime.isAfter(now) && program.endTime.isAfter(now))
        return program;
    }
    return null;
  }

  EpgProgram? nextFor(Channel channel) {
    final now = DateTime.now();
    for (final program in programmesFor(channel)) {
      if (program.startTime.isAfter(now)) return program;
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _archive?.close();
    _service.deferActiveDownload();
    PlaybackWorkPolicy.instance.removeListener(_onPlaybackChanged);
    _timer?.cancel();
    _app.removeListener(_onAppChanged);
    super.dispose();
  }
}

class _TrimmedTimeline {
  final DateTime origin;
  final List<EpgTimelineSlot> slots;
  const _TrimmedTimeline(this.origin, this.slots);
}

/// A download with no programmes must not replace a guide that has some,
/// and must not be treated as the daily success.
@visibleForTesting
bool epgKeepsPreviousGuide({
  required int previousCount,
  required int incomingCount,
}) => incomingCount == 0 && previousCount > 0;

@visibleForTesting
bool epgGuideIsFresh(int incomingCount) => incomingCount > 0;

@visibleForTesting
bool epgGuideNeedsRefresh({
  required bool empty,
  required int programmeCount,
  required bool hasChannels,
  required DateTime? lastRun,
  required int intervalMinutes,
  required DateTime now,
}) {
  if (empty || lastRun == null) return true;
  if (hasChannels && programmeCount == 0) return true;
  if (intervalMinutes <= 0) return false;
  return now.difference(lastRun) >= Duration(minutes: intervalMinutes);
}
