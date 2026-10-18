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
      if (session != null) 'session': session,
      ...data,
    });
    if (events.length > limit) events.removeRange(0, events.length - limit);
  }

  static String errorKind(String reason) {
    final text = reason.toLowerCase();
    if (text.contains('schermo nero')) return 'no_video_frames';
    if (text.contains('403') || text.contains('forbidden')) return 'http_403';
    if (text.contains('404')) return 'http_404';
    if (text.contains('429')) return 'http_429';
    if (text.contains('458') || text.contains('max connections'))
      return 'connection_limit';
    if (text.contains('timeout') || text.contains('secondi')) return 'timeout';
    if (text.contains('codec') || text.contains('decoder')) return 'decoder';
    if (text.contains('network') || text.contains('socket')) return 'network';
    return 'playback_error';
  }

  String report(
    Map<String, Object?> device,
  ) => const JsonEncoder.withIndent('  ').convert({
    'schema': 1,
    'app': 'StellarTV',
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'device': device,
    'events': events,
    'privacy':
        'No URLs, credentials, channel titles, account identifiers or raw error messages.',
    'measurement':
        'open_ready is player readiness; first_video_frame is renderer confirmation. suspected_stall is a stationary media clock, not proof of frozen video.',
  });
}

/// A monotonic media-clock probe: pause/buffering reset rather than report stalls.
class LiveStallProbe {
  Duration? _position;
  Duration? _since;
  bool _reported = false;
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
