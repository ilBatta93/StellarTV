import 'dart:async';
import 'dart:io';
import 'dart:ui' show FrameTiming, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import 'frame_telemetry_store.dart';

/// Device-local frame telemetry. Records only while a measuring session is
/// active, never uploads by itself and keeps bounded aggregates (per-second
/// timeline, slowest frames, startup marks) instead of raw frame lists.
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
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    WidgetsBinding.instance.removeObserver(this);
    _checkpoint();
    notifyListeners();
  }

  void reset() {
    stats.reset();
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
    if (_second.frames == 0 || _timeline.length >= _maxTimeline) return;
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
        context: _section,
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
      'v': 2,
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
      'marks': List.of(_marks),
      'events': List.of(_events),
      'timeline': [
        ..._timeline,
        if (_recording && _second.frames > 0 && _timeline.length < _maxTimeline)
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
