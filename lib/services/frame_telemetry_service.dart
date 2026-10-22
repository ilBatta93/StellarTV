import 'dart:async';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Device-local frame telemetry. Records only while a measuring session is
/// active, never uploads by itself and keeps aggregates instead of raw frames.
class FrameTelemetryService extends ChangeNotifier {
  FrameTelemetryService._();
  static final FrameTelemetryService instance = FrameTelemetryService._();

  /// Frames slower than one 60 Hz interval are perceived as stutter.
  static const jankThresholdUs = 16667;
  static const maxSession = Duration(minutes: 10);

  final FrameStats stats = FrameStats();
  bool _recording = false;
  DateTime? _startedAt;
  Timer? _limit;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  bool get recording => _recording;
  DateTime? get startedAt => _startedAt;

  void start() {
    if (_recording) return;
    stats.reset();
    _recording = true;
    _startedAt = DateTime.now();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _limit = Timer(maxSession, stop);
    notifyListeners();
  }

  void stop() {
    if (!_recording) return;
    _recording = false;
    _limit?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    notifyListeners();
  }

  void reset() {
    stats.reset();
    if (_recording) _startedAt = DateTime.now();
    notifyListeners();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      stats.add(
        buildUs: t.buildDuration.inMicroseconds,
        rasterUs: t.rasterDuration.inMicroseconds,
        totalUs: t.totalSpan.inMicroseconds,
      );
    }
    final now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds >= 500) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  Map<String, Object?> report() => {
        'kind': 'performance',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'platform': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'sessionStartedAt': _startedAt?.toUtc().toIso8601String(),
        ...stats.toJson(),
      };
}

/// Pure aggregate of frame timings, testable without the engine.
class FrameStats {
  int frames = 0;
  int jank = 0;
  int _buildSum = 0;
  int _rasterSum = 0;
  int _totalSum = 0;
  int peakUs = 0;
  int peakBuildUs = 0;
  int peakRasterUs = 0;
  DateTime? peakAt;

  void reset() {
    frames = 0;
    jank = 0;
    _buildSum = 0;
    _rasterSum = 0;
    _totalSum = 0;
    peakUs = 0;
    peakBuildUs = 0;
    peakRasterUs = 0;
    peakAt = null;
  }

  void add({
    required int buildUs,
    required int rasterUs,
    required int totalUs,
  }) {
    frames++;
    _buildSum += buildUs;
    _rasterSum += rasterUs;
    _totalSum += totalUs;
    if (totalUs > FrameTelemetryService.jankThresholdUs) jank++;
    if (totalUs > peakUs) {
      peakUs = totalUs;
      peakBuildUs = buildUs;
      peakRasterUs = rasterUs;
      peakAt = DateTime.now();
    }
  }

  double get avgBuildMs => frames == 0 ? 0 : _buildSum / frames / 1000;
  double get avgRasterMs => frames == 0 ? 0 : _rasterSum / frames / 1000;
  double get avgTotalMs => frames == 0 ? 0 : _totalSum / frames / 1000;
  double get jankPercent => frames == 0 ? 0 : jank * 100 / frames;

  /// Estimated sustained rate: a frame never counts as faster than 60 Hz.
  double get fps {
    if (frames == 0) return 0;
    final ms = avgTotalMs < 1000 / 60 ? 1000 / 60 : avgTotalMs;
    return 1000 / ms;
  }

  double _r(double v) => (v * 10).roundToDouble() / 10;

  Map<String, Object?> toJson() => {
        'frames': frames,
        'jankFrames': jank,
        'jankPercent': _r(jankPercent),
        'fps': _r(fps),
        'avgBuildMs': _r(avgBuildMs),
        'avgRasterMs': _r(avgRasterMs),
        'avgFrameMs': _r(avgTotalMs),
        'peakMs': _r(peakUs / 1000),
        'peakBuildMs': _r(peakBuildUs / 1000),
        'peakRasterMs': _r(peakRasterUs / 1000),
        'peakAt': peakAt?.toUtc().toIso8601String(),
      };
}
