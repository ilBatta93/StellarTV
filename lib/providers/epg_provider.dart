import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/channel.dart';
import '../models/epg_program.dart';
import '../services/epg_channel_match.dart';
import '../services/epg_service.dart';
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
  bool get usePlaylistGuide => _usePlaylist;
  List<String> get manualSources => _manual;
  int get intervalMinutes => _intervalMinutes;
  DateTime? get lastUpdate => _data.fetchedAt ?? _lastRun;
  int get programmeCount => _data.programmeCount;
  int get channelCount => _data.programmes.length;

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
    _setData(cached);
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
      _setData(const EpgData());
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
    _setData(data);
    notifyListeners();
    return true;
  }

  void _setData(EpgData data) {
    final now = DateTime.now();
    _data = epgDataInGuideWindow(data, now);
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
    final due =
        _data.isEmpty ||
        _lastRun == null ||
        (_intervalMinutes > 0 &&
            DateTime.now().difference(_lastRun!) >=
                Duration(minutes: _intervalMinutes));
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
      final data = await _service.fetch(sources);
      if (_disposed) return;
      if (_playbackBlocked || sources.join('|') != _activeSources.join('|')) {
        throw EpgRefreshDeferred();
      }
      _setData(data);
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
      guideIds: _data.programmes.keys.toSet(),
      displayNames: _data.displayNames,
    );
    final m = matcher.match(
      name: channel.name,
      tvgName: channel.tvgName,
      tvgId: channel.tvgId,
    );
    _channelMatch[channel.id] = m;
    return m;
  }

  List<EpgProgram> programmesFor(Channel channel) {
    final match = _guideIdFor(channel);
    if (match == null) return const [];
    return _gridLists[match] ??= _gridProgrammes(match);
  }

  List<EpgProgram> _gridProgrammes(EpgMatch match) {
    final source = _data.programmes[match.id] ?? const <EpgProgram>[];
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

  /// Slots for [channel], built once per guide snapshot. [notBefore] only
  /// hides rows the grid cannot scroll to; it does not sort again.
  List<EpgTimelineSlot> timelineFor(Channel channel, {DateTime? notBefore}) {
    final match = _guideIdFor(channel);
    if (match == null) return const [];
    final slots = _timelines[match] ??= epgTimelineSlots(
      programmesFor(channel),
    );
    if (notBefore == null) return slots;
    final cached = _trimmed[match];
    if (cached != null && cached.origin == notBefore) return cached.slots;
    final trimmed = List<EpgTimelineSlot>.unmodifiable([
      for (final slot in slots)
        if (slot.end.isAfter(notBefore)) slot,
    ]);
    _trimmed[match] = _TrimmedTimeline(notBefore, trimmed);
    return trimmed;
  }

  EpgProgram? nowFor(Channel channel) {
    final now = DateTime.now();
    for (final p in programmesFor(channel)) {
      if (!p.startTime.isAfter(now) && p.endTime.isAfter(now)) return p;
    }
    return null;
  }

  EpgProgram? nextFor(Channel channel) {
    final now = DateTime.now();
    for (final p in programmesFor(channel)) {
      if (p.startTime.isAfter(now)) return p;
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
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
