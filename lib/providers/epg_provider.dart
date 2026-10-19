import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/channel.dart';
import '../models/epg_program.dart';
import '../services/epg_service.dart';
import 'app_provider.dart';

/// TV guide for the live channels. The playlist guide (Xtream xmltv.php) is
/// used automatically; extra XMLTV sources can be added in Settings. The
/// guide refreshes on its own (every 12 hours by default).
class EpgProvider extends ChangeNotifier {
  EpgProvider(this._app) {
    _app.addListener(_onAppChanged);
    _start();
  }

  final AppProvider _app;
  final EpgService _service = EpgService();
  Timer? _timer;

  EpgData _data = const EpgData();
  bool _loading = false;
  String? _error;
  bool _usePlaylist = true;
  List<String> _manual = const [];
  int _intervalMinutes = 1440;
  DateTime? _lastRun;
  String? _scheduledFor;
  Map<String, String>? _nameIndex;
  final Map<String, String?> _channelMatch = {};

  bool get isLoading => _loading;
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
    _setData(await _service.loadCache());
    notifyListeners();
    _schedule();
  }

  void _onAppChanged() {
    // Credentials can arrive after startup (login or cloud restore).
    final signature = _activeSources.join('|');
    if (signature != _scheduledFor) _schedule();
    _channelMatch.clear();
  }

  void _setData(EpgData data) {
    _data = data;
    _nameIndex = null;
    _channelMatch.clear();
  }

  void _schedule() {
    _timer?.cancel();
    _scheduledFor = _activeSources.join('|');
    if (_activeSources.isEmpty) return;
    final due = _data.isEmpty ||
        _lastRun == null ||
        (_intervalMinutes > 0 &&
            DateTime.now().difference(_lastRun!) >=
                Duration(minutes: _intervalMinutes));
    if (due) {
      refresh();
    } else if (_intervalMinutes > 0) {
      final wait = Duration(minutes: _intervalMinutes) -
          DateTime.now().difference(_lastRun!);
      _timer = Timer(wait, refresh);
    }
  }

  /// Downloads the guide now.
  Future<void> refresh() async {
    final sources = _activeSources;
    if (_loading) return;
    if (sources.isEmpty) {
      _error = 'Nessuna fonte EPG: attiva la guida della playlist o aggiungi un indirizzo.';
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _setData(await _service.fetch(sources));
      await _service.markRun();
      _lastRun = DateTime.now();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _loading = false;
      notifyListeners();
      _timer?.cancel();
      if (_intervalMinutes > 0) {
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

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'^\s*[a-z]{2,3}\s*[:|\-]\s*'), '')
      .replaceAll(RegExp(r'\b(fhd|uhd|hd|sd|4k|hevc|h265|backup|\+1)\b'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');

  /// Guide channel id for a playlist channel: tvg-id first, then the name.
  String? _guideIdFor(Channel channel) {
    if (_channelMatch.containsKey(channel.id)) return _channelMatch[channel.id];
    String? id;
    final tvg = channel.tvgId?.trim();
    if (tvg != null && tvg.isNotEmpty) {
      if (_data.programmes.containsKey(tvg)) {
        id = tvg;
      } else {
        final lower = tvg.toLowerCase();
        id = _data.programmes.keys
            .where((k) => k.toLowerCase() == lower)
            .firstOrNull;
      }
    }
    if (id == null) {
      final index = _nameIndex ??= {
        for (final e in _data.displayNames.entries) _norm(e.value): e.key,
        for (final k in _data.programmes.keys) _norm(k): k,
      };
      id = index[_norm(channel.tvgName ?? channel.name)] ??
          index[_norm(channel.name)];
    }
    _channelMatch[channel.id] = id;
    return id;
  }

  List<EpgProgram> programmesFor(Channel channel) {
    final id = _guideIdFor(channel);
    if (id == null) return const [];
    return _data.programmes[id] ?? const [];
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
    _timer?.cancel();
    _app.removeListener(_onAppChanged);
    super.dispose();
  }
}
