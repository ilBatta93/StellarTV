import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import '../models/player_settings.dart';
import 'exo_engine.dart';
import 'mediakit_engine.dart';
import 'playback_engine.dart';

enum SessionStatus { connecting, playing, switching, failed }

class PlaybackSession extends ChangeNotifier {
  PlaybackSession({
    required this.url,
    required this.isLive,
    required this.settings,
    this.startAt,
  }) : _candidates = liveCandidates(url, isLive),
       speed = isLive ? 1.0 : settings.defaultSpeed,
       fitMode = settings.fitMode,
       subtitleDelay = Duration(milliseconds: settings.subtitleDelayMs),
       audioDelay = Duration(milliseconds: settings.audioDelayMs);

  final String url;
  final bool isLive;

  /// Alternative addresses for the same stream. Xtream live channels were
  /// saved without the `/live/` segment (HTTP 404); the standard
  /// `/live/user/pass/id.m3u8` form is tried first, then MPEG-TS.
  final List<String> _candidates;
  int _urlIndex = 0;
  String get currentUrl => _candidates[_urlIndex];

  static final _xtreamLive = RegExp(
    r'^(https?://[^/]+)/(?:live/)?([^/]+)/([^/]+)/(\d+)(?:\.(m3u8|ts))?$',
  );

  static List<String> liveCandidates(String url, bool isLive) {
    if (!isLive) return [url];
    final m = _xtreamLive.firstMatch(url.trim());
    if (m == null || url.contains('/movie/') || url.contains('/series/')) {
      return [url];
    }
    final base = '${m[1]}/live/${m[2]}/${m[3]}/${m[4]}';
    return {'$base.m3u8', '$base.ts', url}.toList();
  }

  final PlayerSettings settings;
  final Duration? startAt;

  PlaybackEngine? _engine;
  SessionStatus _status = SessionStatus.connecting;
  String? _notice;
  String? _error;
  int _generation = 0;
  bool _disposed = false;
  final Map<PlayerEngineType, int> _openCount = {};
  int _serverRefusalRetries = 0;

  double speed;
  double volume = 1.0;
  bool muted = false;
  VideoFitMode fitMode;
  Duration subtitleDelay;
  Duration audioDelay;
  double _boxRatio = 16 / 9;
  Size _lastVideoSize = Size.zero;

  PlaybackEngine? get engine => _engine;
  SessionStatus get status => _status;
  String? get notice => _notice;
  String? get error => _error;
  PlaybackSnapshot get value => _engine?.value ?? const PlaybackSnapshot();

  Future<void> start() => _open(settings.primaryEngine, resumeAt: startAt);

  Future<void> retry() {
    _openCount.clear();
    _serverRefusalRetries = 0;
    _urlIndex = 0;
    return _open(settings.primaryEngine, resumeAt: _resumePoint());
  }

  Future<void> switchEngine(PlayerEngineType type) {
    _openCount.clear();
    return _open(type, resumeAt: _resumePoint());
  }

  Duration? _resumePoint() {
    if (isLive) return null;
    final pos = _engine?.value.position ?? Duration.zero;
    return pos > Duration.zero ? pos : startAt;
  }

  PlaybackEngine _create(PlayerEngineType type) => switch (type) {
    PlayerEngineType.exo => ExoEngine(url: currentUrl, settings: settings),
    PlayerEngineType.mediakit => MediaKitEngine(
      url: currentUrl,
      settings: settings,
      isLive: isLive,
    ),
  };

  Future<void> _open(PlayerEngineType type, {Duration? resumeAt}) async {
    final gen = ++_generation;
    _openCount[type] = (_openCount[type] ?? 0) + 1;
    _retire(_engine);
    final engine = _create(type);
    _engine = engine;
    _lastVideoSize = Size.zero;
    _error = null;
    if (_status != SessionStatus.switching) _status = SessionStatus.connecting;
    _notify();

    try {
      await engine.open().timeout(
        Duration(seconds: settings.startTimeoutSeconds),
        onTimeout: () => throw PlaybackException(
          'Nessuna risposta dopo ${settings.startTimeoutSeconds} secondi',
        ),
      );
      if (gen != _generation) return;
    } catch (e) {
      if (gen != _generation) return;
      await _handleFailure(type, e.toString(), resumeAt);
      return;
    }
    engine.addListener(_onEngineChanged);
    _status = SessionStatus.playing;
    _notify();
    try {
      await _applyInitialState(engine, resumeAt, gen);
    } catch (e) {
      debugPrint('Initial playback state not applied: $e');
    }
  }

  void _retire(PlaybackEngine? engine) {
    if (engine == null) return;
    engine.removeListener(_onEngineChanged);
    // Let the surface unmount before releasing the native player.
    Future<void>.delayed(const Duration(milliseconds: 300), engine.dispose);
  }

  Future<void> _applyInitialState(
    PlaybackEngine engine,
    Duration? resumeAt,
    int gen,
  ) async {
    if (resumeAt != null && resumeAt > Duration.zero) {
      await _seekWhenReady(engine, resumeAt, gen);
    }
    if (speed != 1.0) await engine.setSpeed(speed);
    await engine.setVolume(muted ? 0 : volume);
    await engine.applyFitMode(fitMode, _boxRatio);
    if (engine.supportsDelays) {
      await engine.setSubtitleDelay(subtitleDelay);
      await engine.setAudioDelay(audioDelay);
    }

    // Track lists are populated a moment after playback starts.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (gen != _generation || _disposed) return;
    await _applyTrackPreferences(engine);
  }

  /// Seeks to the resume point once the stream is seekable. mpv and
  /// ExoPlayer ignore a seek issued before the duration is known, which made
  /// "Continua a guardare" restart from the beginning; retry until it lands.
  Future<void> _seekWhenReady(
    PlaybackEngine engine,
    Duration target,
    int gen,
  ) async {
    for (var i = 0; i < 40; i++) {
      if (gen != _generation || _disposed) return;
      if (engine.value.duration > Duration.zero) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    for (var attempt = 0; attempt < 4; attempt++) {
      if (gen != _generation || _disposed) return;
      await engine.seekTo(target);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      final pos = engine.value.position;
      if (pos >= target - const Duration(seconds: 10)) return;
    }
  }

  Future<void> _applyTrackPreferences(PlaybackEngine engine) async {
    try {
      if (engine.supportsAudioTracks) {
        final audio = await engine.getAudioTracks();
        final preferred = audio
            .where(
              (t) => trackMatchesLanguage(t, settings.preferredAudioLanguage),
            )
            .firstOrNull;
        if (preferred != null && !preferred.selected) {
          await engine.selectAudioTrack(preferred);
        }
      }
      if (engine.supportsSubtitleTracks) {
        if (!settings.subtitlesEnabled) {
          await engine.selectSubtitleTrack(null);
        } else {
          final subs = await engine.getSubtitleTracks();
          final preferred = subs
              .where(
                (t) =>
                    trackMatchesLanguage(t, settings.preferredSubtitleLanguage),
              )
              .firstOrNull;
          if (preferred != null) await engine.selectSubtitleTrack(preferred);
        }
      }
    } catch (e) {
      debugPrint('Track preferences not applied: $e');
    }
  }

  void _onEngineChanged() {
    final engine = _engine;
    if (engine == null) return;
    if (engine.value.hasError && _status == SessionStatus.playing) {
      final resumeAt = isLive ? null : engine.value.position;
      _handleFailure(engine.type, engine.value.error!, resumeAt);
      return;
    }
    if (engine.value.size != _lastVideoSize) {
      _lastVideoSize = engine.value.size;
      engine.applyFitMode(fitMode, _boxRatio);
    }
    _notify();
  }

  Future<void> _handleFailure(
    PlayerEngineType failed,
    String reason,
    Duration? resumeAt,
  ) async {
    final lower = reason.toLowerCase();
    final serverRefused =
        lower.contains('458') ||
        lower.contains('-16845') ||
        lower.contains('http 403') ||
        lower.contains('forbidden');
    if (serverRefused) {
      final engine = _engine;
      _engine = null;
      _retire(engine);
      if (_serverRefusalRetries < 2) {
        _serverRefusalRetries++;
        _status = SessionStatus.switching;
        _notice = 'Il server sta liberando la connessione. Riprovo tra poco...';
        _notify();
        await Future<void>.delayed(
          Duration(seconds: _serverRefusalRetries == 1 ? 2 : 5),
        );
        if (_disposed) return;
        await _open(failed, resumeAt: resumeAt);
        return;
      }
      _status = SessionStatus.failed;
      _error =
          'Il server TV ha rifiutato la connessione. Verifica che non ci '
          'siano altri dispositivi collegati con lo stesso abbonamento e riprova.';
      _notify();
      return;
    }
    final next = failed.other;
    final otherReady = _openCount[next] ?? 0;
    final canRetrySelf = _openCount[failed] != null && _openCount[failed]! < 2;
    if (settings.autoFallback && otherReady == 0) {
      _status = SessionStatus.switching;
      _notice =
          '${failed.label} non riesce a riprodurre questo flusso. Passo a ${next.label}...';
      _notify();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (_disposed) return;
      await _open(next, resumeAt: resumeAt);
      return;
    }
    if (settings.autoFallback && canRetrySelf) {
      _status = SessionStatus.switching;
      _notice = 'Nuovo tentativo con ${failed.label}...';
      _notify();
      await Future<void>.delayed(const Duration(seconds: 1));
      if (_disposed) return;
      await _open(failed, resumeAt: resumeAt);
      return;
    }
    if (_urlIndex < _candidates.length - 1) {
      _urlIndex++;
      _openCount.clear();
      _status = SessionStatus.switching;
      _notice = 'Provo un formato alternativo del canale...';
      _notify();
      await Future<void>.delayed(const Duration(seconds: 1));
      if (_disposed) return;
      await _open(settings.primaryEngine, resumeAt: resumeAt);
      return;
    }
    _retire(_engine);
    _engine = null;
    _status = SessionStatus.failed;
    _error = reason;
    _notify();
  }

  void clearNotice() {
    if (_notice == null) return;
    _notice = null;
    _notify();
  }

  Future<void> togglePlay() async {
    final engine = _engine;
    if (engine == null) return;
    if (engine.value.isEnded) {
      await engine.seekTo(Duration.zero);
      await engine.play();
    } else if (engine.value.isPlaying) {
      await engine.pause();
    } else {
      await engine.play();
    }
  }

  Future<void> seekTo(Duration position) async {
    final engine = _engine;
    if (engine == null || isLive) return;
    final max = engine.value.duration;
    var target = position < Duration.zero ? Duration.zero : position;
    if (max > Duration.zero && target > max) target = max;
    await engine.seekTo(target);
  }

  Future<void> seekBy(Duration offset) => seekTo(value.position + offset);

  Future<void> setSpeed(double value) async {
    speed = value;
    await _engine?.setSpeed(value);
    _notify();
  }

  Future<void> setVolume(double value) async {
    volume = value.clamp(0.0, 1.0);
    muted = volume == 0;
    await _engine?.setVolume(volume);
    _notify();
  }

  Future<void> toggleMute() async {
    muted = !muted;
    if (!muted && volume == 0) volume = 1.0;
    await _engine?.setVolume(muted ? 0 : volume);
    _notify();
  }

  Future<void> setFitMode(VideoFitMode mode) async {
    fitMode = mode;
    await _engine?.applyFitMode(mode, _boxRatio);
    _notify();
  }

  void updateBoxRatio(double ratio) {
    if ((ratio - _boxRatio).abs() < 0.01) return;
    _boxRatio = ratio;
    if (fitMode == VideoFitMode.fill) _engine?.applyFitMode(fitMode, ratio);
  }

  Future<void> setSubtitleDelay(Duration delay) async {
    subtitleDelay = delay;
    await _engine?.setSubtitleDelay(delay);
    _notify();
  }

  Future<void> setAudioDelay(Duration delay) async {
    audioDelay = delay;
    await _engine?.setAudioDelay(delay);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    final engine = _engine;
    _engine = null;
    engine?.removeListener(_onEngineChanged);
    engine?.dispose();
    super.dispose();
  }
}
