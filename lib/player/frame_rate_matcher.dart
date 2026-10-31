import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/display_refresh_service.dart';
import 'playback_engine.dart';
import 'playback_session.dart';

/// Reads the frame rate of each new stream once and, when [enabled], asks
/// the display for the matching refresh rate. [fps] feeds the player info.
class FrameRateMatcher extends ChangeNotifier {
  FrameRateMatcher({required this.enabled, DisplayRefreshService? display})
    : _display = display ?? DisplayRefreshService.instance;

  final bool enabled;
  final DisplayRefreshService _display;

  /// mpv and ExoPlayer may report the rate a moment after the first picture.
  static const attempts = 6;
  static const retryDelay = Duration(seconds: 1);

  double? _fps;
  double? get fps => _fps;

  PlaybackEngine? _engine;
  String? _stream;
  bool _disposed = false;

  /// Call on every session change; [stream] identifies what is tuned, so a
  /// channel opened in place on the same engine is read again.
  void update(PlaybackSession session, String stream) {
    final engine = session.engine;
    if (_disposed ||
        engine == null ||
        session.status != SessionStatus.playing ||
        !session.value.isPlaying ||
        engine.audioOnly) {
      return;
    }
    if (identical(engine, _engine) && stream == _stream) return;
    _engine = engine;
    _stream = stream;
    if (_fps != null) {
      _fps = null;
      notifyListeners();
    }
    unawaited(_sample(engine, stream));
  }

  bool _current(PlaybackEngine engine, String stream) =>
      !_disposed && identical(engine, _engine) && stream == _stream;

  Future<void> _sample(PlaybackEngine engine, String stream) async {
    for (var i = 0; i < attempts; i++) {
      if (i > 0) await Future<void>.delayed(retryDelay);
      if (!_current(engine, stream)) return;
      final fps = await engine.videoFrameRate();
      if (!_current(engine, stream)) return;
      if (fps == null) continue;
      _fps = fps;
      notifyListeners();
      if (enabled) await _display.matchVideo(fps);
      return;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (enabled) _display.release();
    super.dispose();
  }
}
