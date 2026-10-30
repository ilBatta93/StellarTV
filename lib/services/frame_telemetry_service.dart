import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:ui' show FrameTiming, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import 'frame_telemetry_store.dart';

/// Device-local frame telemetry. Records only while a measuring session is
/// active, never uploads by itself and keeps bounded aggregates (per-second
/// timeline, slowest frames, startup marks) instead of raw frame lists.
///
/// Frame timings alone miss an unresponsive app: a busy main isolate or a
/// slow native player delays keys without producing slow frames. The
/// [responsiveness] aggregate covers that (event-loop lag, key latency,
/// player command latency, rebuilds per screen).
class FrameTelemetryService extends ChangeNotifier with WidgetsBindingObserver {
  FrameTelemetryService._();
  static final FrameTelemetryService instance = FrameTelemetryService._();

  /// Frames slower than one 60 Hz interval are perceived as stutter.
  static const jankThresholdUs = 16667;
  static const maxSession = Duration(minutes: 10);
  static const autoStartKey = 'perf_telemetry_autostart_v1';
  static const _maxMarks = 80;
  static const _maxTimeline = 600;
  static const _maxEvents = 60;

  /// Process start reference: set as early as possible in main().
  static final Stopwatch sinceLaunch = Stopwatch()..start();

  final FrameStats stats = FrameStats();
  final ResponsivenessStats responsiveness = ResponsivenessStats();
  final NavigatorObserver observer = _TelemetryRouteObserver();
  bool _recording = false;
  bool _autoStarted = false;
  bool autoStartEnabled = false;
  DateTime? _startedAt;
  Timer? _limit;
  Timer? _sampler;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
  String _route = 'avvio';
  String _section = 'avvio';
  final List<(Object, String)> _overlaySections = [];
  Timer? _loopProbe;
  final Stopwatch _loopClock = Stopwatch();
  int _lastProbeMs = 0;
  static const _loopProbeMs = 50;
  int? _firstFrameMs;
  final List<Map<String, Object?>> _marks = [];
  final List<Map<String, Object?>> _timeline = [];
  final List<Map<String, Object?>> _events = [];
  _Second _second = _Second(0);
  int _peakRssMb = 0;
  int _peakImageMb = 0;
  String? _appVersion;
  FrameTelemetryStore? _store;
  Map<String, Object?>? previousReport;
  int? _rssMb;
  DateTime _lastCheckpoint = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _initializing;

  Future<void> initializeStore() => _initializing ??= () async {
    try {
      final dir = await getApplicationSupportDirectory();
      final store = FrameTelemetryStore(dir.path);
      previousReport = await store.recover();
      _store = store;
      notifyListeners();
    } catch (_) {
      // Failed recovery must not overwrite the only recoverable file.
    }
  }();

  void _checkpoint() {
    final store = _store;
    if (store == null || _startedAt == null) return;
    _lastCheckpoint = DateTime.now();
    unawaited(store.save(report()).catchError((_) {}));
  }

  bool get recording => _recording;
  DateTime? get startedAt => _startedAt;

  /// Called first thing in main(): starts measuring before the first frame
  /// when the user enabled "start with the app".
  Future<void> startIfAutoEnabled() async {
    await initializeStore();
    try {
      final prefs = await SharedPreferences.getInstance();
      autoStartEnabled = prefs.getBool(autoStartKey) ?? false;
    } catch (_) {
      autoStartEnabled = false;
    }
    if (autoStartEnabled) {
      _autoStarted = true;
      start();
      mark('main');
    }
    unawaited(() async {
      try {
        final p = await PackageInfo.fromPlatform();
        _appVersion = '${p.version}+${p.buildNumber}';
      } catch (_) {}
    }());
  }

  Future<void> setAutoStart(bool value) async {
    autoStartEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(autoStartKey, value);
  }

  /// Named milestone (startup steps, heavy jobs). Cheap no-op when idle.
  void mark(String label) {
    // Named milestone: previously tracked _lastMark; now recorded in marks.
    if (!_recording || _marks.length >= _maxMarks) return;
    _marks.add({'t': sinceLaunch.elapsedMilliseconds, 'label': label});
  }

  void _event(String label) {
    if (!_recording || _events.length >= _maxEvents) return;
    _events.add({'t': sinceLaunch.elapsedMilliseconds, 'event': label});
    if (label == 'memoria scarsa' || label.startsWith('stato app:')) {
      _checkpoint();
    }
  }

  void start() {
    if (_recording) return;
    unawaited(initializeStore());
    stats.reset();
    responsiveness.reset();
    _marks.clear();
    _timeline.clear();
    _events.clear();
    _peakRssMb = 0;
    _peakImageMb = 0;
    _recording = true;
    _startedAt = DateTime.now();
    _second = _Second(sinceLaunch.elapsedMilliseconds ~/ 1000);
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    _loopClock
      ..reset()
      ..start();
    _lastProbeMs = 0;
    _loopProbe = Timer.periodic(
      const Duration(milliseconds: _loopProbeMs),
      (_) => _probeLoop(),
    );
    _limit = Timer(maxSession, stop);
    _sample();
    _sampler = Timer.periodic(const Duration(seconds: 1), (_) {
      _sample();
      if (DateTime.now().difference(_lastCheckpoint).inSeconds >= 5) {
        _checkpoint();
      }
    });
    _checkpoint();
    if (_firstFrameMs == null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _firstFrameMs ??= sinceLaunch.elapsedMilliseconds;
        mark('primo fotogramma');
      });
    }
    notifyListeners();
  }

  void stop() {
    if (!_recording) return;
    _flushSecond();
    _recording = false;
    _limit?.cancel();
    _sampler?.cancel();
    _loopProbe?.cancel();
    _loopClock.stop();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _checkpoint();
    notifyListeners();
  }

  void reset() {
    stats.reset();
    responsiveness.reset();
    _timeline.clear();
    _events.clear();
    _marks.clear();
    _peakRssMb = 0;
    _peakImageMb = 0;
    _second = _Second(sinceLaunch.elapsedMilliseconds ~/ 1000);
    if (_recording) _startedAt = DateTime.now();
    _checkpoint();
    notifyListeners();
  }

  void _setRoute(String name) {
    _route = name;
    _event('schermata: $name');
  }

  /// Called at tab changes to name the visible section (home, diretta, film,
  /// serie, player). Shown as context in slow-frame entries instead of the
  /// route type + last mark, which stuck the guide mark across screens.
  void setSection(String section) {
    _section = section;
  }

  /// Names a full-screen layer above the tabs (the player). Returns a token
  /// for [leaveSection]: a player replacing another is disposed after the
  /// new one entered, so a plain "restore previous" would mislabel it.
  Object enterSection(String section) {
    final token = Object();
    _overlaySections.add((token, section));
    return token;
  }

  void leaveSection(Object token) =>
      _overlaySections.removeWhere((entry) => identical(entry.$1, token));

  String get _context =>
      _overlaySections.isEmpty ? _section : _overlaySections.last.$2;

  /// Counts builds of a screen per visible section: `diretta@player` is the
  /// live page rebuilding while hidden under the player.
  void countBuild(String screen) {
    if (!_recording) return;
    responsiveness.addBuild('$screen@$_context');
  }

  /// Time from a player command (play, pause, seek, native poll) to its
  /// completion. A busy native thread shows here before it shows as jank.
  void recordCommand(String name, int ms) {
    if (!_recording) return;
    responsiveness.addCommand(name, ms, sinceLaunch.elapsedMilliseconds);
  }

  /// A periodic timer fires late by exactly how long the main isolate was
  /// busy: that is what a remote press waits before being handled.
  void _probeLoop() {
    final now = _loopClock.elapsedMilliseconds;
    final lag = now - _lastProbeMs - _loopProbeMs;
    _lastProbeMs = now;
    if (lag < 0) return;
    _second.addLag(lag);
    responsiveness.addLag(lag, sinceLaunch.elapsedMilliseconds, _context);
  }

  bool _onKey(KeyEvent event) {
    if (!_recording || event is! KeyDownEvent) return false;
    final receivedUs = Timeline.now;
    // Android stamps keys with the monotonic clock Timeline.now also reads:
    // the difference is how long the press waited before reaching Dart.
    // Other sources may stamp differently, so implausible values are dropped.
    final stampMs = event.timeStamp.inMilliseconds;
    final waited = receivedUs ~/ 1000 - stampMs;
    final dispatchMs = stampMs > 0 && waited >= 0 && waited <= 10000
        ? waited
        : null;
    final key = event.logicalKey.debugName ?? event.logicalKey.keyLabel;
    final context = _context;
    final at = sinceLaunch.elapsedMilliseconds;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_recording) return;
      responsiveness.addKey(
        key: key,
        frameMs: (Timeline.now - receivedUs) ~/ 1000,
        dispatchMs: dispatchMs,
        atMs: at,
        context: context,
      );
    });
    // A key with no visible effect would otherwise wait for an unrelated
    // frame and inflate the measure.
    SchedulerBinding.instance.scheduleFrame();
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _event('stato app: ${state.name}');

  @override
  void didHaveMemoryPressure() => _event('memoria scarsa');

  void _sample() {
    try {
      final rss = ProcessInfo.currentRss >> 20;
      _rssMb = rss;
      if (rss > _peakRssMb) _peakRssMb = rss;
    } catch (_) {}
    final img = PaintingBinding.instance.imageCache.currentSizeBytes >> 20;
    if (img > _peakImageMb) _peakImageMb = img;
  }

  void _flushSecond() {
    if (!_second.worthKeeping || _timeline.length >= _maxTimeline) return;
    _timeline.add(_second.toJson(_route));
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final total = t.totalSpan.inMicroseconds;
      final sec = sinceLaunch.elapsedMilliseconds ~/ 1000;
      if (sec != _second.sec) {
        _flushSecond();
        _second = _Second(sec);
      }
      _second.add(total);
      stats.add(
        buildUs: t.buildDuration.inMicroseconds,
        rasterUs: t.rasterDuration.inMicroseconds,
        totalUs: total,
        vsyncUs: t.vsyncOverhead.inMicroseconds,
        atMs: sinceLaunch.elapsedMilliseconds,
        // Use the visible section, not the route type + last mark which was
        // sticking 'guida: pronta' to every subsequent screen.
        context: _context,
      );
    }
    final now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds >= 500) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  Map<String, Object?> report() {
    final view = PlatformDispatcher.instance.implicitView;
    final cache = PaintingBinding.instance.imageCache;
    return {
      'kind': 'performance',
      'v': 3,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'appVersion': _appVersion,
      'platform': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'cpuCores': Platform.numberOfProcessors,
      'sessionStartedAt': _startedAt?.toUtc().toIso8601String(),
      'startedWithApp': _autoStarted,
      'uptimeMs': sinceLaunch.elapsedMilliseconds,
      'firstFrameMs': _firstFrameMs,
      if (view != null) ...{
        'screen':
            '${view.physicalSize.width.toInt()}x${view.physicalSize.height.toInt()}',
        'pixelRatio': view.devicePixelRatio,
        'refreshRate': view.display.refreshRate,
      },
      'memory': {
        'rssMb': _rssMb,
        'peakRssMb': _peakRssMb,
        'imageCacheMb': cache.currentSizeBytes >> 20,
        'peakImageCacheMb': _peakImageMb,
        'imageCacheLimitMb': cache.maximumSizeBytes >> 20,
        'images': cache.currentSize,
        'imageCacheLimit': cache.maximumSize,
        'liveImages': cache.liveImageCount,
        'pendingImages': cache.pendingImageCount,
      },
      ...stats.toJson(),
      'responsiveness': responsiveness.toJson(),
      'marks': List.of(_marks),
      'events': List.of(_events),
      'timeline': [
        ..._timeline,
        if (_recording &&
            _second.worthKeeping &&
            _timeline.length < _maxTimeline)
          _second.toJson(_route),
      ],
      'recordingAtCheckpoint': _recording,
    };
  }
}

class _TelemetryRouteObserver extends NavigatorObserver {
  String _name(Route<dynamic>? r) => r == null
      ? 'avvio'
      : r.runtimeType.toString().replaceAll(RegExp(r'<.*>'), '');
  @override
  void didPush(Route route, Route? previousRoute) =>
      FrameTelemetryService.instance._setRoute(_name(route));
  @override
  void didPop(Route route, Route? previousRoute) =>
      FrameTelemetryService.instance._setRoute(_name(previousRoute));
  @override
  void didReplace({Route? newRoute, Route? oldRoute}) =>
      FrameTelemetryService.instance._setRoute(_name(newRoute));
}

class _Second {
  _Second(this.sec);
  final int sec;
  int frames = 0;
  int jank = 0;
  int worstUs = 0;
  int worstLagMs = 0;

  /// A second without frames still matters when the main isolate stalled.
  bool get worthKeeping => frames > 0 || worstLagMs >= 100;

  void addLag(int ms) {
    if (ms > worstLagMs) worstLagMs = ms;
  }

  void add(int us) {
    frames++;
    if (us > FrameTelemetryService.jankThresholdUs) jank++;
    if (us > worstUs) worstUs = us;
  }

  Map<String, Object?> toJson(String route) => {
    's': sec,
    'f': frames,
    'j': jank,
    'max': (worstUs / 100).round() / 10,
    'lag': worstLagMs,
    'r': route,
  };
}

/// Pure aggregate of frame timings, testable without the engine.
class FrameStats {
  static const slowestKept = 15;
  int frames = 0;
  int jank = 0;
  int _buildSum = 0;
  int _rasterSum = 0;
  int _totalSum = 0;
  int _vsyncSum = 0;
  int peakUs = 0;
  int peakBuildUs = 0;
  int peakRasterUs = 0;
  DateTime? peakAt;
  String? peakContext;

  /// Frame duration buckets: <=16.6, <=33, <=50, <=100, <=250, >250 ms.
  static const _limitsUs = [16667, 33333, 50000, 100000, 250000];
  final List<int> histogram = List.filled(6, 0);
  int buildBound = 0;
  int rasterBound = 0;
  final List<Map<String, Object?>> slowest = [];

  void reset() {
    frames = 0;
    jank = 0;
    _buildSum = 0;
    _rasterSum = 0;
    _totalSum = 0;
    _vsyncSum = 0;
    peakUs = 0;
    peakBuildUs = 0;
    peakRasterUs = 0;
    peakAt = null;
    peakContext = null;
    histogram.fillRange(0, histogram.length, 0);
    buildBound = 0;
    rasterBound = 0;
    slowest.clear();
  }

  void add({
    required int buildUs,
    required int rasterUs,
    required int totalUs,
    int vsyncUs = 0,
    int? atMs,
    String? context,
  }) {
    frames++;
    _buildSum += buildUs;
    _rasterSum += rasterUs;
    _totalSum += totalUs;
    _vsyncSum += vsyncUs;
    var b = 0;
    while (b < _limitsUs.length && totalUs > _limitsUs[b]) {
      b++;
    }
    histogram[b]++;
    if (totalUs > FrameTelemetryService.jankThresholdUs) {
      jank++;
      if (buildUs >= rasterUs) {
        buildBound++;
      } else {
        rasterBound++;
      }
      _keepSlow(totalUs, buildUs, rasterUs, vsyncUs, atMs, context);
    }
    if (totalUs > peakUs) {
      peakUs = totalUs;
      peakBuildUs = buildUs;
      peakRasterUs = rasterUs;
      peakAt = DateTime.now();
      peakContext = context;
    }
  }

  void _keepSlow(
    int total,
    int build,
    int raster,
    int vsync,
    int? at,
    String? context,
  ) {
    if (slowest.length >= slowestKept &&
        (slowest.last['ms'] as double) * 1000 >= total) {
      return;
    }
    slowest.add({
      'ms': _r(total / 1000),
      'buildMs': _r(build / 1000),
      'rasterMs': _r(raster / 1000),
      'vsyncMs': _r(vsync / 1000),
      't': ?at,
      'at': ?context,
    });
    slowest.sort((a, b) => (b['ms'] as double).compareTo(a['ms'] as double));
    if (slowest.length > slowestKept) slowest.removeLast();
  }

  double get avgBuildMs => frames == 0 ? 0 : _buildSum / frames / 1000;
  double get avgRasterMs => frames == 0 ? 0 : _rasterSum / frames / 1000;
  double get avgTotalMs => frames == 0 ? 0 : _totalSum / frames / 1000;
  double get avgVsyncMs => frames == 0 ? 0 : _vsyncSum / frames / 1000;
  double get jankPercent => frames == 0 ? 0 : jank * 100 / frames;

  /// Estimated sustained rate: a frame never counts as faster than 60 Hz.
  double get fps {
    if (frames == 0) return 0;
    final ms = avgTotalMs < 1000 / 60 ? 1000 / 60 : avgTotalMs;
    return 1000 / ms;
  }

  static double _r(double v) => (v * 10).roundToDouble() / 10;

  Map<String, Object?> toJson() => {
    'frames': frames,
    'jankFrames': jank,
    'jankPercent': _r(jankPercent),
    'fps': _r(fps),
    'avgBuildMs': _r(avgBuildMs),
    'avgRasterMs': _r(avgRasterMs),
    'avgVsyncMs': _r(avgVsyncMs),
    'avgFrameMs': _r(avgTotalMs),
    'jankBuildBound': buildBound,
    'jankRasterBound': rasterBound,
    'histogram': {
      'le16': histogram[0],
      'le33': histogram[1],
      'le50': histogram[2],
      'le100': histogram[3],
      'le250': histogram[4],
      'gt250': histogram[5],
    },
    'peakMs': _r(peakUs / 1000),
    'peakBuildMs': _r(peakBuildUs / 1000),
    'peakRasterMs': _r(peakRasterUs / 1000),
    'peakAt': peakAt?.toUtc().toIso8601String(),
    'peakContext': peakContext,
    'slowest': List.of(slowest),
  };
}

/// Pure aggregate of how fast the app answers, testable without the engine.
class ResponsivenessStats {
  static const slowestKept = 12;

  /// A key answered within this time feels immediate on a TV.
  static const slowKeyMs = 150;

  /// Event-loop lag buckets: <=50, <=100, <=250, <=1000, >1000 ms.
  static const _lagLimits = [50, 100, 250, 1000];
  final List<int> lagHistogram = List.filled(5, 0);
  int lagSamples = 0;
  int maxLagMs = 0;
  final List<Map<String, Object?>> slowestLags = [];

  int keys = 0;
  int slowKeys = 0;
  int _keyFrameSum = 0;
  int maxKeyFrameMs = 0;
  int dispatchSamples = 0;
  int _dispatchSum = 0;
  int maxDispatchMs = 0;
  final List<Map<String, Object?>> slowestKeys = [];

  final Map<String, CommandStat> commands = {};
  final Map<String, int> builds = {};

  void reset() {
    lagHistogram.fillRange(0, lagHistogram.length, 0);
    lagSamples = 0;
    maxLagMs = 0;
    slowestLags.clear();
    keys = 0;
    slowKeys = 0;
    _keyFrameSum = 0;
    maxKeyFrameMs = 0;
    dispatchSamples = 0;
    _dispatchSum = 0;
    maxDispatchMs = 0;
    slowestKeys.clear();
    commands.clear();
    builds.clear();
  }

  void addLag(int ms, int atMs, String context) {
    lagSamples++;
    var b = 0;
    while (b < _lagLimits.length && ms > _lagLimits[b]) {
      b++;
    }
    lagHistogram[b]++;
    if (ms > maxLagMs) maxLagMs = ms;
    if (ms >= 100) {
      _keep(slowestLags, {'ms': ms, 't': atMs, 'at': context});
    }
  }

  void addKey({
    required String key,
    required int frameMs,
    int? dispatchMs,
    int? atMs,
    String? context,
  }) {
    keys++;
    _keyFrameSum += frameMs;
    if (frameMs > maxKeyFrameMs) maxKeyFrameMs = frameMs;
    if (dispatchMs != null) {
      dispatchSamples++;
      _dispatchSum += dispatchMs;
      if (dispatchMs > maxDispatchMs) maxDispatchMs = dispatchMs;
    }
    final total = frameMs + (dispatchMs ?? 0);
    if (total < slowKeyMs) return;
    slowKeys++;
    _keep(slowestKeys, {
      'ms': total,
      'frameMs': frameMs,
      'dispatchMs': ?dispatchMs,
      'key': key,
      't': ?atMs,
      'at': ?context,
    });
  }

  void addCommand(String name, int ms, [int? atMs]) =>
      (commands[name] ??= CommandStat()).add(ms, atMs);

  void addBuild(String label) => builds[label] = (builds[label] ?? 0) + 1;

  double get avgKeyFrameMs => keys == 0 ? 0 : _keyFrameSum / keys;
  double get avgDispatchMs =>
      dispatchSamples == 0 ? 0 : _dispatchSum / dispatchSamples;

  /// Main-isolate stalls long enough for a remote press to feel ignored.
  int get stallsOver250 => lagHistogram[3] + lagHistogram[4];

  /// The player command with the worst single time, if any was measured.
  MapEntry<String, CommandStat>? get slowestCommand {
    MapEntry<String, CommandStat>? worst;
    for (final entry in commands.entries) {
      if (worst == null || entry.value.maxMs > worst.value.maxMs) {
        worst = entry;
      }
    }
    return worst;
  }

  static void _keep(
    List<Map<String, Object?>> list,
    Map<String, Object?> entry,
  ) {
    final value = entry['ms'] as int;
    if (list.length >= slowestKept && (list.last['ms'] as int) >= value) {
      return;
    }
    list.add(entry);
    list.sort((a, b) => (b['ms'] as int).compareTo(a['ms'] as int));
    if (list.length > slowestKept) list.removeLast();
  }

  Map<String, Object?> toJson() {
    final topBuilds = builds.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {
      'loopLag': {
        'samples': lagSamples,
        'maxMs': maxLagMs,
        'histogram': {
          'le50': lagHistogram[0],
          'le100': lagHistogram[1],
          'le250': lagHistogram[2],
          'le1000': lagHistogram[3],
          'gt1000': lagHistogram[4],
        },
        'slowest': List.of(slowestLags),
      },
      'keys': {
        'count': keys,
        'slow': slowKeys,
        'avgToFrameMs': FrameStats._r(avgKeyFrameMs),
        'maxToFrameMs': maxKeyFrameMs,
        'dispatchSamples': dispatchSamples,
        'avgDispatchMs': FrameStats._r(avgDispatchMs),
        'maxDispatchMs': maxDispatchMs,
        'slowest': List.of(slowestKeys),
      },
      'commands': {
        for (final entry in commands.entries) entry.key: entry.value.toJson(),
      },
      'builds': {
        for (final entry in topBuilds.take(40)) entry.key: entry.value,
      },
    };
  }
}

/// Latency of one kind of player command.
class CommandStat {
  int count = 0;
  int _sum = 0;
  int maxMs = 0;
  int over250 = 0;
  int? maxAt;

  void add(int ms, [int? atMs]) {
    count++;
    _sum += ms;
    if (ms > 250) over250++;
    if (ms > maxMs) {
      maxMs = ms;
      maxAt = atMs;
    }
  }

  double get avgMs => count == 0 ? 0 : _sum / count;

  Map<String, Object?> toJson() => {
    'n': count,
    'avgMs': FrameStats._r(avgMs),
    'maxMs': maxMs,
    'over250': over250,
    'maxAt': ?maxAt,
  };
}
