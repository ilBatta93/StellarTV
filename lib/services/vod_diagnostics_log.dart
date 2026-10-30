import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'live_diagnostics_log.dart';

/// Opt-in record of film and series playback. Only allowlisted numbers,
/// booleans and short engine tokens enter a report: never an address, a
/// title, a credential or a player message.
class VodDiagnosticsLog {
  VodDiagnosticsLog({this.limit = 1000, String? salt})
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

  /// One shared wording for both records: an error bucket is an error bucket.
  static String errorKind(String reason) =>
      LiveDiagnosticsLog.errorKind(reason);

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

  static const _types = {
    'attempt_start',
    'observation_started_midstream',
    'playback_info',
    'open_ready',
    'first_video_frame',
    'buffer_start',
    'buffer_end',
    'buffer_interrupted',
    'suspected_stall',
    'frame_drop',
    'cache_low',
    'av_drift',
    'position_jump',
    'position_back',
    'error',
    'attempt_end',
  };

  static const _numbers = {
    'attempt',
    'elapsedMs',
    'startupMs',
    'durationMs',
    'positionMs',
    'stallMs',
    'jumpMs',
    'expectedMs',
    'droppedFrames',
    'cacheMs',
    'avSyncMs',
    'fps',
    'httpStatus',
  };

  static const _engines = {
    'mpv',
    'mediaKit',
    'mediakit',
    'exoPlayer',
    'exoplayer',
    'exo',
  };
  static const _formats = {'hls', 'ts', 'other'};
  static const _hwdec = {
    'no',
    'auto',
    'auto-safe',
    'auto-copy',
    'mediacodec',
    'mediacodec-copy',
    'videotoolbox',
    'videotoolbox-copy',
    'd3d11',
    'd3d11-copy',
    'vaapi',
    'vdpau',
    'nvdec',
    'cuda',
  };
  static const _codecs = {
    'h264',
    'avc',
    'avc1',
    'hevc',
    'hev1',
    'hvc1',
    'h265',
    'vp9',
    'vp09',
    'av1',
    'av01',
    'mpeg2',
    'mpeg4',
    'vc1',
    'mjpeg',
    'theora',
  };
  static const _categories = {
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
  };

  static Map<String, Object?> _safeEvent(Map<String, Object?> raw) => {
    for (final e in raw.entries)
      if ({'at', 'type', ..._numbers}.contains(e.key) &&
          (e.value is bool ||
              e.value is num ||
              e.key == 'at' &&
                  e.value is String &&
                  DateTime.tryParse(e.value as String) != null ||
              e.key == 'type' && _types.contains(e.value)))
        e.key: e.value,
    if (_engines.contains(raw['engine'])) 'engine': raw['engine'],
    if (_formats.contains(raw['format'])) 'format': raw['format'],
    if (_hwdec.contains(raw['hwdec'])) 'hwdec': raw['hwdec'],
    if (_codecs.contains(raw['codec'])) 'codec': raw['codec'],
    if (raw['preview'] is bool) 'preview': raw['preview'],
    if (raw['softwareDecode'] is bool) 'softwareDecode': raw['softwareDecode'],
    if (raw['midPlay'] is bool) 'midPlay': raw['midPlay'],
    if (_categories.contains(raw['category'])) 'category': raw['category'],
  };

  String report(Map<String, Object?> device) =>
      const JsonEncoder.withIndent('  ').convert({
        'schema': 1,
        'app': 'StellarTV',
        'kind': 'vod',
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'device': _safeDevice(device),
        'events': events.map(_safeEvent).toList(),
        'privacy': 'No URLs, credentials, titles, account identifiers or raw error messages.',
        'measurement': 'droppedFrames is the player counter of discarded pictures; cacheMs is the read-ahead still in memory; avSyncMs is the audio clock minus the video clock; jumpMs is a media-clock move that does not match the wall clock.',
      });
}

/// One stutter signal: a short type plus the allowlisted numbers behind it.
class VodStutterSignal {
  const VodStutterSignal(this.type, this.data);
  final String type;
  final Map<String, Object?> data;
}

/// Consecutive one-second samples of film/series playback turned into stutter
/// signals. A deliberate seek is announced with [markSeek], so a jump the
/// viewer made is never mistaken for a stutter. Pure: no player, no I/O.
class VodStutterProbe {
  Duration? _position;
  Duration? _elapsed;
  Duration? _stallSince;
  bool _stallReported = false;
  int? _dropped;
  final Map<String, Duration> _lastSeen = {};

  static const cooldown = Duration(seconds: 5);
  static const jumpTolerance = Duration(milliseconds: 700);
  static const cacheFloorMs = 1500;
  static const driftFloorMs = 50;

  /// The viewer moved the position: the next sample cannot be a stutter.
  void markSeek() {
    _position = null;
    _elapsed = null;
    _stallSince = null;
    _stallReported = false;
  }

  List<VodStutterSignal> check({
    required Duration elapsed,
    required Duration position,
    required bool playing,
    required bool buffering,
    required double speed,
    int? droppedFrames,
    int? cacheMs,
    int? avSyncMs,
  }) {
    final out = <VodStutterSignal>[];
    if (!playing || buffering) {
      _position = null;
      _elapsed = null;
      _stallSince = null;
      _stallReported = false;
      _dropped = droppedFrames;
      return out;
    }
    final prev = _position;
    final prevAt = _elapsed;
    final prevDropped = _dropped;
    _position = position;
    _elapsed = elapsed;
    _dropped = droppedFrames;

    // 1. The media clock stands still while the player says it is playing.
    if (prev != null && prev == position) {
      final since = _stallSince ??= elapsed;
      if (!_stallReported && elapsed - since >= const Duration(seconds: 2)) {
        _stallReported = true;
        _add(out, elapsed, 'suspected_stall', {
          'stallMs': (elapsed - since).inMilliseconds,
          'positionMs': position.inMilliseconds,
        });
      }
    } else {
      _stallSince = null;
      _stallReported = false;
    }

    // 2. The media clock moved by an amount the wall clock cannot explain.
    //    Skipped while the clock stands still: that is already a stall.
    if (prev != null &&
        prevAt != null &&
        elapsed > prevAt &&
        _stallSince == null) {
      final delta = position - prev;
      final expected = Duration(
        microseconds: ((elapsed - prevAt).inMicroseconds * speed).round(),
      );
      if (delta < Duration.zero) {
        _add(out, elapsed, 'position_back', {
          'jumpMs': -delta.inMilliseconds,
          'positionMs': position.inMilliseconds,
        });
      } else if ((delta - expected).abs() > jumpTolerance) {
        _add(out, elapsed, 'position_jump', {
          'jumpMs': delta.inMilliseconds,
          'expectedMs': expected.inMilliseconds,
          'positionMs': position.inMilliseconds,
        });
      }
    }

    // 3. The renderer threw pictures away.
    if (prevDropped != null &&
        droppedFrames != null &&
        droppedFrames > prevDropped) {
      _add(out, elapsed, 'frame_drop', {
        'droppedFrames': droppedFrames - prevDropped,
      });
    }

    // 4. The read-ahead nearly ran dry: the next frame may arrive late.
    if (cacheMs != null && cacheMs < cacheFloorMs) {
      _add(out, elapsed, 'cache_low', {'cacheMs': cacheMs});
    }

    // 5. Audio and video clocks drifted apart.
    if (avSyncMs != null && avSyncMs.abs() > driftFloorMs) {
      _add(out, elapsed, 'av_drift', {'avSyncMs': avSyncMs});
    }

    return out;
  }

  /// One signal per type every [cooldown]: a real stutter repeats, and a
  /// report full of the same second would hide everything around it.
  void _add(
    List<VodStutterSignal> out,
    Duration elapsed,
    String type,
    Map<String, Object?> data,
  ) {
    final last = _lastSeen[type];
    if (last != null && elapsed - last < cooldown) return;
    _lastSeen[type] = elapsed;
    out.add(VodStutterSignal(type, data));
  }
}
