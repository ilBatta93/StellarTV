import 'dart:async';

import 'package:flutter/widgets.dart';

import '../player/playback_engine.dart';
import 'vod_diagnostics_log.dart';
import 'vod_diagnostics_service.dart';

/// Observes only: never seeks, pauses or changes playback settings.
class VodDiagnosticsTracker {
  final service = VodDiagnosticsService.instance;
  final clock = Stopwatch();
  VodStutterProbe probe = VodStutterProbe();
  Duration? bufferingAt;
  bool firstFrame = false;
  String? session;
  int attempt = 0;
  bool observed = false;
  bool running = false;
  bool _infoRecorded = false;
  bool _sampling = false;

  void begin(
    String url,
    String engine,
    bool preview,
    bool software, {
    bool observed = false,
    String? userAgent,
  }) {
    this.observed = observed;
    running = true;
    session ??=
        '${DateTime.now().microsecondsSinceEpoch}-${service.log.streamId(url)}';
    attempt++;
    clock
      ..reset()
      ..start();
    probe = VodStutterProbe();
    bufferingAt = null;
    firstFrame = false;
    _infoRecorded = false;
    service.record(
      observed ? 'observation_started_midstream' : 'attempt_start',
      session: session,
      data: {
        'stream': service.log.streamId(url),
        'attempt': attempt,
        'engine': engine,
        'preview': preview,
        'softwareDecode': software,
        'format': Uri.tryParse(url)?.path.endsWith('.m3u8') == true
            ? 'hls'
            : Uri.tryParse(url)?.path.endsWith('.ts') == true
            ? 'ts'
            : 'other',
      },
    );
  }

  void event(String type, {Map<String, Object?> data = const {}}) {
    service.record(
      type,
      session: session,
      data: {
        'attempt': attempt,
        'elapsedMs': clock.elapsedMilliseconds,
        ...data,
      },
    );
  }

  /// A deliberate seek: the next sample must not be read as a jump.
  void markSeek() => probe.markSeek();

  /// mpv answers the metric reads, so sampling is async. One read at a
  /// time: a slow player must not pile up samples that compete with frames.
  void sample(PlaybackEngine engine) {
    if (_sampling) return;
    _sampling = true;
    unawaited(_sample(engine).whenComplete(() => _sampling = false));
  }

  Future<void> _sample(PlaybackEngine engine) async {
    if (!service.enabled || !running) return;
    final v = engine.value;
    final metrics = await engine.metrics();
    if (!running) return;

    final active =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (engine.videoFrameRendered == true && !firstFrame) {
      firstFrame = true;
      event(
        'first_video_frame',
        data: {if (!observed) 'startupMs': clock.elapsedMilliseconds},
      );
    }
    if (active && v.isBuffering && bufferingAt == null) {
      bufferingAt = clock.elapsed;
      event('buffer_start');
    } else if ((!v.isBuffering || !active) && bufferingAt != null) {
      final since = bufferingAt;
      bufferingAt = null;
      if (since != null) {
        event(
          'buffer_end',
          data: {'durationMs': (clock.elapsed - since).inMilliseconds},
        );
      }
    }
    final dropped = _int(metrics['frameDropCount']);
    final cacheMs = _cacheMs(metrics);
    final avSyncMs = _avSyncMs(metrics);
    final fps = _int(metrics['estimatedFps']);
    if (!_infoRecorded) {
      _infoRecorded = true;
      event(
        'playback_info',
        data: {
          'hwdec': metrics['hwdecCurrent'],
          'codec': _codec(metrics['videoCodec']),
          'fps': ?fps,
          'cacheMs': ?cacheMs,
        },
      );
    }
    for (final signal in probe.check(
      elapsed: clock.elapsed,
      position: v.position,
      playing: active && v.isPlaying,
      buffering: v.isBuffering,
      speed: v.speed,
      droppedFrames: dropped,
      cacheMs: cacheMs,
      avSyncMs: avSyncMs,
    )) {
      event(signal.type, data: signal.data);
    }
  }

  static int? _int(Object? value) => value is num ? value.round() : null;

  /// mpv reports the read-ahead in seconds; a negative or absurd value is
  /// simply no measurement at all.
  static int? _cacheMs(Map<String, Object?> metrics) {
    final seconds = metrics['cacheSeconds'];
    if (seconds is! num || seconds.isNaN || seconds.isInfinite) return null;
    if (seconds < 0) return null;
    return (seconds * 1000).round();
  }

  /// mpv reports audio minus video drift in seconds.
  static int? _avSyncMs(Map<String, Object?> metrics) {
    final seconds = metrics['avSyncSeconds'];
    if (seconds is! num || seconds.isNaN || seconds.isInfinite) return null;
    return (seconds * 1000).round();
  }

  /// "h264 (High) (H.264)" -> "h264": only the short token is allowlisted.
  static String? _codec(Object? value) {
    if (value is! String) return null;
    final token = value.trim().toLowerCase().split(RegExp(r'[^a-z0-9]')).first;
    return token.isEmpty || token.length > 16 ? null : token;
  }

  void end() {
    if (!running) return;
    running = false;
    final since = bufferingAt;
    if (since != null) {
      event(
        'buffer_interrupted',
        data: {'durationMs': (clock.elapsed - since).inMilliseconds},
      );
    }
    bufferingAt = null;
    event('attempt_end');
    clock.stop();
  }
}
