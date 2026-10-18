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
    service.record(
      observed ? 'observation_started_midstream' : 'attempt_start',
      session: session,
      data: {
        'stream': service.log.streamId(url),
        'attempt': attempt,
        'engine': engine,
        'preview': preview,
        'softwareDecode': software,
        if (userAgent != null) 'userAgent': userAgent,
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
      if (since != null)
        event(
          'buffer_end',
          data: {'durationMs': (clock.elapsed - since).inMilliseconds},
        );
    }
    if (probe.check(
      elapsed: clock.elapsed,
      position: v.position,
      playing: active && v.isPlaying,
      buffering: v.isBuffering,
    )) {
      event(
        'suspected_stall',
        data: {
          'positionMs': v.position.inMilliseconds,
          'videoFrameConfirmed': firstFrame,
        },
      );
    }
  }

  void end() {
    if (!running) return;
    running = false;
    final since = bufferingAt;
    if (since != null)
      event(
        'buffer_interrupted',
        data: {'durationMs': (clock.elapsed - since).inMilliseconds},
      );
    bufferingAt = null;
    event('attempt_end');
    clock.stop();
  }
}
