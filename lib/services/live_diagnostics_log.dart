import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Only structured, allowlisted data enters reports; never copy player errors.
class LiveDiagnosticsLog {
  LiveDiagnosticsLog({this.limit = 1000, String? salt})
    : salt =
          salt ??
          List.generate(16, (_) => Random.secure().nextInt(256)).join('-');
  final int limit;
  final String salt;
  bool enabled = false;
  final List<Map<String, Object?>> events = [];
  String streamId(String address) =>
      sha256.convert(utf8.encode('$salt:$address')).toString().substring(0, 16);
  void add(
    String type, {
    String? session,
    Map<String, Object?> data = const {},
  }) {
    if (!enabled) return;
    events.add({
      'at': DateTime.now().toUtc().toIso8601String(),
      'type': type,
      'session': ?session,
      ...data,
    });
    if (events.length > limit) events.removeRange(0, events.length - limit);
  }

  static String errorKind(String reason) {
    final text = reason.toLowerCase();
    if (text.contains('schermo nero')) return 'no_video_frames';
    if (text.contains('nessun video dal server')) return 'no_video_startup';
    if (text.contains('503') || text.contains('service unavailable')) {
      return 'http_503';
    }
    if (text.contains('403') || text.contains('forbidden')) return 'http_403';
    if (text.contains('404')) return 'http_404';
    if (text.contains('429')) return 'http_429';
    if (text.contains('458') || text.contains('max connections')) {
      return 'connection_limit';
    }
    if (text.contains('timeout') || text.contains('secondi')) return 'timeout';
    if (text.contains('codec') || text.contains('decoder')) return 'decoder';
    if (text.contains('network') || text.contains('socket')) return 'network';
    return 'playback_error';
  }

  static Map<String, Object?> _safeDevice(Map<String, Object?> raw) => {
    for (final e in raw.entries)
      if ({
            'platform',
            'osVersion',
            'tv',
            'fireTv',
            'version',
            'build',
            'manufacturer',
            'model',
            'sdk',
          }.contains(e.key) &&
          (e.value is bool ||
              e.value is num ||
              e.value is String &&
                  (e.value as String).length < 200 &&
                  !RegExp(
                    r'https?://|password|username|token=',
                    caseSensitive: false,
                  ).hasMatch(e.value as String)))
        e.key: e.value,
  };

  /// Numeric/boolean fields of `engine_state`.
  static const engineStateKeys = <String>{
    'playing',
    'buffering',
    'audioOnly',
    'videoWidth',
    'videoHeight',
    'frameDropCount',
    'decoderFrameDropCount',
    'estimatedFps',
    'cacheSeconds',
    'avSyncSeconds',
    'cacheKib',
  };

  /// Numeric/boolean fields of the opt-in stream probe (no text, no hosts).
  static final probeKeys = <String>{
    for (final p in ['probe', 'variant', 'seg']) ...{
      '${p}Status',
      '${p}FirstByteMs',
      '${p}Bytes',
      '${p}ReadMs',
      '${p}TsSync',
      '${p}Redirects',
      '${p}HostChanged',
      '${p}ReadStalled',
    },
    'playlistSegments',
    'variantSegments',
    'targetDuration',
    'playlistLive',
    'segHostChanged',
    'probeTimeout',
  };
  static Map<String, Object?> _safeEvent(Map<String, Object?> raw) => {
    for (final e in raw.entries)
      if ({
            'at',
            'type',
            'attempt',
            'elapsedMs',
            'startupMs',
            'durationMs',
            'positionMs',
            'preview',
            'softwareDecode',
            'videoFrameConfirmed',
            'midPlay',
            'httpStatus',
            'frameDelta',
            'renderedFrames',
            'frozenMs',
            ...engineStateKeys,
            ...probeKeys,
          }.contains(e.key) &&
          (e.value is bool ||
              e.value is num ||
              e.key == 'at' &&
                  e.value is String &&
                  DateTime.tryParse(e.value as String) != null ||
              e.key == 'type' &&
                  {
                    'attempt_start',
                    'observation_started_midstream',
                    'attempt_end',
                    'error',
                    'first_video_frame',
                    'buffer_start',
                    'buffer_end',
                    'buffer_interrupted',
                    'suspected_stall',
                    'clock_pinned',
                    'picture_frozen',
                    'picture_resumed',
                    'engine_state',
                    'open_ready',
                    'stream_probe',
                  }.contains(e.value)))
        e.key: e.value,
    if ({
      'exoPlayer',
      'mpv',
      'mediaKit',
      'exoplayer',
      'exo',
      'mediakit',
    }.contains(raw['engine']))
      'engine': raw['engine'],
    if ({'hls', 'ts', 'other'}.contains(raw['format'])) 'format': raw['format'],
    // Codec and decoder names only: lowercase, short, no separators of a URL.
    for (final k in const ['videoCodec', 'hwdecCurrent'])
      if (raw[k] is String &&
          RegExp(r'^[a-z0-9_\-]{1,24}$').hasMatch(raw[k] as String))
        k: raw[k],
    if ({'vlc', 'android', 'smarters', 'custom'}.contains(raw['userAgent']))
      'userAgent': raw['userAgent'],
    for (final k in const ['probeKind', 'variantKind', 'segKind'])
      if ({
        'm3u8',
        'mpegts',
        'video',
        'binary',
        'html',
        'json',
        'text',
        'other',
        'none',
      }.contains(raw[k]))
        k: raw[k],
    if ({'master', 'media'}.contains(raw['playlistType']))
      'playlistType': raw['playlistType'],
    if ({'socket', 'tls', 'http', 'other'}.contains(raw['probeFailure']))
      'probeFailure': raw['probeFailure'],
    if ({
      'no_video_frames',
      'no_video_startup',
      'http_503',
      'http_403',
      'http_404',
      'http_429',
      'connection_limit',
      'timeout',
      'decoder',
      'network',
      'playback_error',
    }.contains(raw['category']))
      'category': raw['category'],
    // attempt_end close reason (no free text).
    if ({
      'left',
      'replaced',
      'health',
      'startup',
      'error',
    }.contains(raw['reason']))
      'reason': raw['reason'],
  };

  String report(Map<String, Object?> device) =>
      const JsonEncoder.withIndent('  ').convert({
        'schema': 3,
        'app': 'StellarTV',
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'device': _safeDevice(device),
        'events': events.map(_safeEvent).toList(),
        'privacy': 'No URLs, credentials, channel titles, account identifiers or raw error messages.',
        'measurement': 'open_ready is player readiness; first_video_frame is renderer confirmation. clock_pinned means the TS live clock never moved beyond ~500 ms (not a stall, emitted once per attempt). suspected_stall is a media clock that moved and then froze; frameDelta (native frames since the freeze) is positive when the picture is still flowing and zero when both clock and picture are stuck. picture_frozen is a native frame count that stopped for 3 s while playing and not buffering (black or frozen picture), picture_resumed its end; renderedFrames is the native count, frozenMs a freeze still open when the attempt ended. engine_state (at 5 s and 15 s) is what the engine reports: playing, buffering, audioOnly (no video track found), video size, codec, hardware decoder in use and dropped frames. attempt_end.reason: left=user navigated away, replaced=channel switched, health=engine recovery, startup=no first frame, error=player error.',
      });
}

/// A monotonic media-clock probe: pause/buffering reset rather than report stalls.
class LiveStallProbe {
  Duration? _position;
  Duration? _since;
  bool _reported = false;
  int? lastRenderedFrameCount;

  void snapshotFrameCount(int? count) {
    lastRenderedFrameCount = count;
  }

  bool check({
    required Duration elapsed,
    required Duration position,
    required bool playing,
    required bool buffering,
  }) {
    if (!playing || buffering || _position != position) {
      _position = position;
      _since = elapsed;
      _reported = false;
      return false;
    }
    final since = _since;
    if (!_reported &&
        since != null &&
        elapsed - since >= const Duration(seconds: 5)) {
      _reported = true;
      return true;
    }
    return false;
  }
}
