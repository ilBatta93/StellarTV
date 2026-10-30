import 'dart:async';

import 'package:flutter/widgets.dart';

import '../player/playback_engine.dart';
import 'live_diagnostics_service.dart';
import 'live_diagnostics_log.dart';

/// Observes only: never reconnects, seeks, pauses or changes playback settings.
class LiveDiagnosticsTracker {
  final service = LiveDiagnosticsService.instance;
  final clock = Stopwatch();
  LiveStallProbe probe = LiveStallProbe();
  Duration? bufferingAt;
  bool firstFrame = false;
  String? session;
  int attempt = 0;
  bool observed = false;
  bool running = false;

  // clock_pinned state: emitted at most once per attempt when the position
  // stays at or below ~500 ms for the whole session (TS live clock pinned).
  bool _clockPinnedEmitted = false;

  // Native frame count, read every sample. A count that stops while the
  // player says it is playing is a frozen or black picture.
  int? _frames;
  Duration _framesMovedAt = Duration.zero;
  Duration? _frozenAt;
  static const _frozenAfter = Duration(seconds: 3);

  // engine_state: what the engine reports a few seconds in, so a black
  // picture can be told apart from a stalled stream, a missing video track
  // or a decoder that cannot keep up.
  static const _stateAt = [Duration(seconds: 5), Duration(seconds: 15)];
  int _stateSent = 0;

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
    probe = LiveStallProbe();
    bufferingAt = null;
    firstFrame = false;
    _clockPinnedEmitted = false;
    _frames = null;
    _framesMovedAt = Duration.zero;
    _frozenAt = null;
    _stateSent = 0;
    service.record(
      observed ? 'observation_started_midstream' : 'attempt_start',
      session: session,
      data: {
        'stream': service.log.streamId(url),
        'attempt': attempt,
        'engine': engine,
        'preview': preview,
        'softwareDecode': software,
        'userAgent': ?userAgent,
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

  void sample(PlaybackEngine engine) {
    if (!service.enabled) return;
    final v = engine.value;
    final active =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (engine.videoFrameRendered == true && !firstFrame) {
      firstFrame = true;
      event(
        'first_video_frame',
        data: {if (!observed) 'startupMs': clock.elapsedMilliseconds},
      );
      // Baseline, so the first suspected_stall already carries frameDelta.
      probe.snapshotFrameCount(engine.renderedFrameCount);
    }
    _samplePicture(engine, playing: active && v.isPlaying && !v.isBuffering);
    if (_stateSent < _stateAt.length && clock.elapsed >= _stateAt[_stateSent]) {
      _stateSent++;
      unawaited(_reportState(engine));
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

    // clock_pinned: after the first frame the position never exceeds ~500 ms.
    // This is the TS-live clock-pinned condition, not a stall. Emitted once.
    if (firstFrame && !_clockPinnedEmitted) {
      final posMs = v.position.inMilliseconds;
      if (posMs <= 500 && clock.elapsedMilliseconds >= 3000) {
        _clockPinnedEmitted = true;
        event(
          'clock_pinned',
          data: {'positionMs': posMs, 'renderedFrames': ?_frames},
        );
        // Not a stall — do not also emit suspected_stall for a pinned clock.
        return;
      }
    }

    // suspected_stall: clock had moved but is now stuck. Adds frameDelta so
    // the reader knows whether the picture is still flowing.
    if (probe.check(
      elapsed: clock.elapsed,
      position: v.position,
      playing: active && v.isPlaying,
      buffering: v.isBuffering,
    )) {
      final rendered = engine.renderedFrameCount;
      final lastRendered = probe.lastRenderedFrameCount;
      final frameDelta = (rendered != null && lastRendered != null)
          ? rendered - lastRendered
          : null;
      event(
        'suspected_stall',
        data: {
          'positionMs': v.position.inMilliseconds,
          'videoFrameConfirmed': firstFrame,
          'frameDelta': ?frameDelta,
        },
      );
      // Snapshot the current frame count so the next delta is relative.
      probe.snapshotFrameCount(rendered);
    }
  }

  void _samplePicture(PlaybackEngine engine, {required bool playing}) {
    final count = engine.renderedFrameCount;
    if (count == null || !firstFrame) return;
    final moved = _frames == null || count != _frames;
    _frames = count;
    if (moved || !playing) {
      _framesMovedAt = clock.elapsed;
      final since = _frozenAt;
      if (moved && since != null) {
        _frozenAt = null;
        event(
          'picture_resumed',
          data: {'durationMs': (clock.elapsed - since).inMilliseconds},
        );
      }
      return;
    }
    if (_frozenAt == null && clock.elapsed - _framesMovedAt >= _frozenAfter) {
      _frozenAt = _framesMovedAt;
      event(
        'picture_frozen',
        data: {
          'positionMs': engine.value.position.inMilliseconds,
          'renderedFrames': count,
        },
      );
    }
  }

  Future<void> _reportState(PlaybackEngine engine) async {
    final at = attempt;
    Map<String, Object?> metrics;
    try {
      metrics = await engine.metrics();
    } catch (_) {
      metrics = const {};
    }
    if (!running || attempt != at) return;
    final v = engine.value;
    event(
      'engine_state',
      data: engineStateData(
        playing: v.isPlaying,
        buffering: v.isBuffering,
        positionMs: v.position.inMilliseconds,
        audioOnly: engine.audioOnly,
        firstFrame: firstFrame,
        size: v.size,
        renderedFrames: engine.renderedFrameCount,
        metrics: metrics,
      ),
    );
  }

  /// [reason] must be one of: left, replaced, health, startup, error.
  void end({String reason = 'left'}) {
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
    final frozen = _frozenAt;
    event(
      'attempt_end',
      data: {
        'reason': reason,
        'renderedFrames': ?_frames,
        if (frozen != null) 'frozenMs': (clock.elapsed - frozen).inMilliseconds,
      },
    );
    clock.stop();
  }
}

/// Fields of an `engine_state` event. mpv answers with text: numbers are
/// parsed and only short codec or decoder names are kept.
Map<String, Object?> engineStateData({
  required bool playing,
  required bool buffering,
  required int positionMs,
  required bool audioOnly,
  required bool firstFrame,
  required Size size,
  required int? renderedFrames,
  required Map<String, Object?> metrics,
}) {
  final out = <String, Object?>{
    'playing': playing,
    'buffering': buffering,
    'positionMs': positionMs,
    'audioOnly': audioOnly,
    'videoFrameConfirmed': firstFrame,
    if (size.width > 0) 'videoWidth': size.width.round(),
    if (size.height > 0) 'videoHeight': size.height.round(),
    'renderedFrames': ?renderedFrames,
  };
  const numbers = {
    'frameDropCount',
    'decoderFrameDropCount',
    'estimatedFps',
    'cacheSeconds',
    'avSyncSeconds',
    'cacheKib',
  };
  final name = RegExp(r'^[a-z0-9_\-]{1,24}$');
  metrics.forEach((key, value) {
    if (numbers.contains(key)) {
      final n = value is num ? value : num.tryParse('$value');
      if (n != null && n.isFinite) out[key] = n;
    } else if (key == 'hwdecCurrent' || key == 'videoCodec') {
      final text = '$value'.toLowerCase();
      if (name.hasMatch(text)) out[key] = text;
    }
  });
  return out;
}
