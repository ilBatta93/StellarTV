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
        event('clock_pinned', data: {'positionMs': posMs});
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
    event('attempt_end', data: {'reason': reason});
    clock.stop();
  }
}
