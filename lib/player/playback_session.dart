import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import '../models/player_settings.dart';
import 'decoder_memory.dart';
import '../services/live_diagnostics_service.dart';
import '../services/live_diagnostics_tracker.dart';
import '../services/live_diagnostics_log.dart';
import 'exo_engine.dart';
import 'mediakit_engine.dart';
import 'playback_engine.dart';

enum SessionStatus { connecting, playing, switching, failed }

/// One planned way to open the stream: an engine on one of the addresses.
class _Attempt {
  const _Attempt(this.engine, this.url);
  final PlayerEngineType engine;
  final String url;
}

/// Owns at most ONE native player at a time.
///
/// Field reports (Fire TV, Google TV, Chromecast): live channels showed a
/// black picture and then the app closed with every engine. The old session
/// created the next player while the previous one was still alive (released
/// 300 ms later), and failures switched engine before trying the other
/// addresses of the channel: one bad address produced a storm of native
/// players and provider connections, ending in a native crash or in the
/// provider refusing the stream. Now every swap fully releases the previous
/// player first, alternative addresses are tried with the same engine, the
/// number of attempts is bounded and errors of stale players are ignored.
class PlaybackSession extends ChangeNotifier {
  PlaybackSession({
    required this.url,
    required this.isLive,
    required this.settings,
    this.startAt,
    this.previewMode = false,
    this.previewFallback = false,
    this.engineFactory,
  }) : _candidates = liveCandidates(
         url,
         isLive,
         format: settings.liveStreamFormat,
       ),
       speed = isLive ? 1.0 : settings.defaultSpeed,
       fitMode = settings.fitMode,
       subtitleDelay = Duration(milliseconds: settings.subtitleDelayMs),
       audioDelay = Duration(milliseconds: settings.audioDelayMs);

  final String url;
  final bool isLive;

  /// Small/parallel players (Diretta preview, MultiView tiles).
  final bool previewMode;

  /// MultiView tiles: a tile whose hardware decoder is busy (cheap TV sticks
  /// have one) may fall back to mpv/FFmpeg instead of staying black.
  final bool previewFallback;

  /// Allows deterministic playback/lifecycle tests without a native decoder.
  final PlaybackEngine Function(PlayerEngineType)? engineFactory;

  /// Alternative addresses for the same stream. Xtream live channels were
  /// saved without the `/live/` segment (HTTP 404); the standard
  /// `/live/user/pass/id.m3u8` form is tried first, then MPEG-TS.
  final List<String> _candidates;
  String _currentUrl = '';
  String get currentUrl =>
      _currentUrl.isEmpty ? _candidates.first : _currentUrl;

  static final _xtreamLive = RegExp(
    r'^(https?://[^/]+)/(?:live/)?([^/]+)/([^/]+)/(\d+)(?:\.(m3u8|ts))?$',
  );

  static List<String> liveCandidates(
    String url,
    bool isLive, {
    LiveStreamFormat format = LiveStreamFormat.auto,
  }) {
    if (!isLive) return [url];
    final m = _xtreamLive.firstMatch(url.trim());
    if (m == null || url.contains('/movie/') || url.contains('/series/')) {
      return [url];
    }
    final base = '${m[1]}/live/${m[2]}/${m[3]}/${m[4]}';
    // The provider's own address first (most Xtream servers deliver live
    // channels as native MPEG-TS; forcing HLS caused transcoding, audio with
    // a black picture and a second connection refused by the server). Only
    // addresses missing the `/live/` segment (HTTP 404) are rewritten.
    final original = url.trim();
    return switch (format) {
      LiveStreamFormat.ts => {'$base.ts', '$base.m3u8', original}.toList(),
      LiveStreamFormat.m3u8 => {'$base.m3u8', '$base.ts', original}.toList(),
      LiveStreamFormat.auto => {
        if (original.contains('/live/')) original,
        '$base.ts',
        '$base.m3u8',
        original,
      }.toList(),
    };
  }

  /// Engine used by preview/MultiView tiles: ExoPlayer on Android (Java,
  /// hardware decoder, cheap to create/release, safe to run several at
  /// once); the configured engine elsewhere.
  static PlayerEngineType previewEngine(PlayerSettings settings) =>
      defaultTargetPlatform == TargetPlatform.android
      ? PlayerEngineType.exo
      : settings.primaryEngine;

  final PlayerSettings settings;
  final Duration? startAt;

  PlaybackEngine? _engine;
  SessionStatus _status = SessionStatus.connecting;
  String? _notice;
  String? _error;
  int _generation = 0;
  int _failedGeneration = -1;
  bool _disposed = false;
  int _serverRefusalRetries = 0;
  int _reconnects = 0;

  /// When the current player started playing: a drop after a long stable
  /// stretch is a new incident, so the reconnect budget is refilled.
  DateTime? _playingSince;
  bool _softwareDecode = false;
  List<_Attempt> _plan = const [];
  int _attempt = 0;
  Future<void> _releasing = Future<void>.value();

  double speed;
  double volume = 1.0;
  bool muted = false;
  VideoFitMode fitMode;
  Duration subtitleDelay;
  Duration audioDelay;
  double _boxRatio = 16 / 9;
  Size _lastVideoSize = Size.zero;

  PlaybackEngine? get engine => _engine;

  /// Completes when every player of this session has been fully released
  /// (useful after [dispose] before opening another stream).
  Future<void> get released => _releasing;
  SessionStatus get status => _status;
  String? get notice => _notice;
  String? get error => _error;
  PlaybackSnapshot get value => _engine?.value ?? const PlaybackSnapshot();

  /// Channels already known to give a black picture with the hardware
  /// decoder open directly in mpv with FFmpeg software decoding.
  PlayerEngineType get _firstEngine => _softwareDecode
      ? PlayerEngineType.mediakit
      : previewMode
      ? previewEngine(settings)
      : settings.primaryEngine;

  /// Every address with [primary] first; then, when allowed, every address
  /// with the fallback engine. Previews never change engine.
  List<_Attempt> _buildPlan(PlayerEngineType primary, {bool fallback = true}) {
    // MultiView: when the TV runs out of hardware decoders a second address
    // would fail the same way, so each address is tried with ExoPlayer and
    // then at once with mpv before moving on.
    if (fallback &&
        settings.autoFallback &&
        previewMode &&
        previewFallback &&
        primary.other != primary) {
      return [
        for (final u in _candidates) ...[
          _Attempt(primary, u),
          _Attempt(primary.other, u),
        ],
      ];
    }
    final plan = [for (final u in _candidates) _Attempt(primary, u)];
    final other = primary.other;
    if (fallback &&
        (!previewMode || previewFallback) &&
        settings.autoFallback &&
        other != primary) {
      plan.addAll([for (final u in _candidates) _Attempt(other, u)]);
    }
    return plan;
  }

  LiveDiagnosticsTracker? _diagnostics;
  Timer? _diagnosticTimer;
  bool _diagnosticListening = false;
  bool _diagnosticEnabled = false;
  void _diagnosticPreference() {
    if (_disposed) return;
    final enabled = LiveDiagnosticsService.instance.enabled;
    if (enabled == _diagnosticEnabled) return;
    _diagnosticEnabled = enabled;
    if (!enabled) {
      _diagnosticTimer?.cancel(); _diagnosticTimer = null; _diagnostics = null;
      return;
    }
    _diagnostics ??= LiveDiagnosticsTracker();
    final current = _engine;
    if (current != null) {
      _diagnostics?.begin(currentUrl, current.type.name, previewMode, _softwareDecode, observed: true);
    }
    _diagnosticTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final engine = _engine;
      if (engine != null) _diagnostics?.sample(engine);
    });
  }

  Future<void> start() async {
    if (isLive && !_diagnosticListening) {
      _diagnosticListening = true;
      LiveDiagnosticsService.instance.addListener(_diagnosticPreference);
      unawaited(LiveDiagnosticsService.instance.initialize());
      _diagnosticPreference();
    }
    if (isLive) {
      try {
        await DecoderMemory.ensureLoaded();
      } catch (_) {}
      if (_disposed) return;
      // Software decoding is a decoder choice, not an engine switch: it
      // stays available even when automatic engine fallback is off.
      if ((!previewMode || previewFallback) &&
          DecoderMemory.needsSoftware(url))
        _softwareDecode = true;
    }
    _plan = _buildPlan(_firstEngine);
    _attempt = 0;
    return _openAttempt(resumeAt: startAt);
  }

  Future<void> retry() {
    _serverRefusalRetries = 0;
    _reconnects = 0;
    _plan = _buildPlan(_firstEngine);
    _attempt = 0;
    return _openAttempt(resumeAt: _resumePoint());
  }

  Future<void> switchEngine(PlayerEngineType type) {
    _serverRefusalRetries = 0;
    _reconnects = 0;
    // Keep the address that works, if one was already found.
    final working = _currentUrl.isEmpty ? null : _currentUrl;
    _plan = [
      if (working != null) _Attempt(type, working),
      for (final u in _candidates)
        if (u != working) _Attempt(type, u),
    ];
    _attempt = 0;
    return _openAttempt(resumeAt: _resumePoint());
  }

  Duration? _resumePoint() {
    if (isLive) return null;
    final pos = _engine?.value.position ?? Duration.zero;
    return pos > Duration.zero ? pos : startAt;
  }

  PlaybackEngine _create(PlayerEngineType type, String address) =>
      engineFactory?.call(type) ??
      switch (type) {
        PlayerEngineType.exo => ExoEngine(
          url: address,
          settings: settings,
          shared: previewMode,
        ),
        PlayerEngineType.mediakit => MediaKitEngine(
          url: address,
          settings: settings,
          isLive: isLive,
          previewMode: previewMode,
          softwareDecode: _softwareDecode,
        ),
      };

  /// Detaches the current player, unmounts its view and releases it
  /// completely (decoder, surface and provider connection) before the
  /// returned future completes. Releases are serialized.
  Future<void> _releaseCurrent() {
    final old = _engine;
    if (old == null) return _releasing;
    _diagnostics?.end();
    _engine = null;
    old.removeListener(_onEngineChanged);
    _notify(); // the view unmounts on the next frame
    _releasing = _releasing.then((_) async {
      try {
        await old.setVolume(0).timeout(const Duration(milliseconds: 500));
      } catch (_) {}
      // Let the surface/texture leave the screen before freeing it.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      try {
        final Object? result = (old as dynamic).dispose();
        if (result is Future) {
          // A deadline is not proof that the decoder has been released.
          // Never permit the replacement to overlap a pending disposal.
          await result;
        }
      } catch (e) {
        debugPrint('Player release failed: $e');
      }
      // Providers with a single connection need a moment to free it.
      await Future<void>.delayed(Duration(milliseconds: isLive ? 450 : 150));
    });
    return _releasing;
  }

  Future<void> _openAttempt({Duration? resumeAt}) async {
    final gen = ++_generation;
    _hlsWatch?.cancel();
    await _releaseCurrent();
    if (gen != _generation || _disposed || _plan.isEmpty) return;
    final attempt = _plan[_attempt.clamp(0, _plan.length - 1)];
    _diagnostics?.begin(attempt.url, attempt.engine.name, previewMode, _softwareDecode);
    _currentUrl = attempt.url;
    final engine = _create(attempt.engine, attempt.url);
    _engine = engine;
    _lastVideoSize = Size.zero;
    _error = null;
    if (_status != SessionStatus.switching) _status = SessionStatus.connecting;
    _notify();

    try {
      await engine
          .open(initialVolume: muted ? 0 : volume)
          .timeout(
            Duration(seconds: settings.startTimeoutSeconds),
            onTimeout: () => throw PlaybackException(
              'Nessuna risposta dopo ${settings.startTimeoutSeconds} secondi',
            ),
          );
    } catch (e) {
      if (gen != _generation || _disposed || _engine != engine) return;
      await _handleFailure(gen, e.toString(), resumeAt, midPlay: false);
      return;
    }
    if (gen != _generation || _disposed || _engine != engine) return;
    engine.addListener(_onEngineChanged);
    if (engine.value.hasError) {
      await _handleFailure(gen, engine.value.error ?? 'Errore video', resumeAt,
          midPlay: false);
      return;
    }
    _diagnostics?.event('open_ready');
    _watchHlsFrames(engine, gen, resumeAt);
    _status = SessionStatus.playing;
    _notice = null;
    // Fresh stream (new channel or reconnect): timeshift starts from here.
    _shift = Duration.zero;
    _pausedAt = null;
    _liveStartedAt = isLive ? DateTime.now() : null;
    _playingSince = DateTime.now();
    if (isLive && _softwareDecode) {
      // Persist only after the fallback actually opens, not on the original
      // failure: broken provider connections must not poison decoder memory.
      unawaited(DecoderMemory.remember(url));
    }
    _notify();
    try {
      await _applyInitialState(engine, resumeAt, gen);
    } catch (e) {
      debugPrint('Initial playback state not applied: $e');
    }
  }

  Future<void> _applyInitialState(
    PlaybackEngine engine,
    Duration? resumeAt,
    int gen,
  ) async {
    if (gen != _generation || _disposed) return;
    if (resumeAt != null && resumeAt > Duration.zero) {
      await _seekWhenReady(engine, resumeAt, gen);
    }
    if (gen != _generation || _disposed) return;
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

  Timer? _hlsWatch;

  /// Xtream .m3u8 addresses are often fake playlists that never deliver a
  /// segment: the player is "ready" but no picture ever arrives. When the
  /// first frame is missing shortly after opening, move to the next address
  /// (normally raw MPEG-TS) instead of waiting for the long start timeout.
  void _watchHlsFrames(PlaybackEngine engine, int gen, Duration? resumeAt) {
    _hlsWatch?.cancel();
    if (!isLive || Uri.tryParse(_currentUrl)?.path.endsWith('.m3u8') != true) return;
    if (_attempt >= _plan.length - 1) return;
    _hlsWatch = Timer(const Duration(milliseconds: 3500), () {
      if (_disposed || gen != _generation || _engine != engine) return;
      if (engine.videoFrameRendered == true) return;
      if (engine.value.hasError) return;
      _handleFailure(gen, 'Playlist HLS senza video dopo 3 secondi (timeout)',
          resumeAt, midPlay: false);
    });
  }

  void _onEngineChanged() {
    final engine = _engine;
    if (engine == null) return;
    if (engine.value.hasError && _status == SessionStatus.playing) {
      final resumeAt = isLive ? null : engine.value.position;
      _handleFailure(_generation, engine.value.error!, resumeAt, midPlay: true);
      return;
    }
    if (engine.value.size != _lastVideoSize) {
      _lastVideoSize = engine.value.size;
      engine.applyFitMode(fitMode, _boxRatio);
    }
    _notify();
  }

  static bool _isServerRefusal(String reason) {
    final lower = reason.toLowerCase();
    return lower.contains('458') ||
        lower.contains('-16845') ||
        lower.contains('http 403') ||
        lower.contains('forbidden') ||
        lower.contains('429') ||
        lower.contains('max connections');
  }

  /// One failure is handled per attempt: errors repeated by the same player
  /// or reported by a player already replaced are ignored.
  Future<void> _handleFailure(
    int gen,
    String reason,
    Duration? resumeAt, {
    required bool midPlay,
  }) async {
    if (_disposed || gen != _generation || _failedGeneration == gen) return;
    _failedGeneration = gen;
    _diagnostics?.event('error', data: {'category': LiveDiagnosticsLog.errorKind(reason), 'midPlay': midPlay});
    final since = _playingSince;
    if (midPlay &&
        since != null &&
        DateTime.now().difference(since) > const Duration(seconds: 15)) {
      _reconnects = 0;
      _serverRefusalRetries = 0;
    }
    final failed = _plan.isEmpty
        ? settings.primaryEngine
        : _plan[_attempt.clamp(0, _plan.length - 1)].engine;

    // The provider refuses a second connection: wait until it frees the
    // previous one, then retry the same attempt (never a storm of players).
    if (_isServerRefusal(reason)) {
      if (_serverRefusalRetries < 2) {
        _serverRefusalRetries++;
        _status = SessionStatus.switching;
        _notice = 'Il server sta liberando la connessione. Riprovo tra poco...';
        await _releaseCurrent();
        await Future<void>.delayed(
          Duration(seconds: _serverRefusalRetries == 1 ? 2 : 5),
        );
        if (_disposed || gen != _generation) return;
        await _openAttempt(resumeAt: resumeAt);
        return;
      }
      await _releaseCurrent();
      if (gen != _generation) return;
      _status = SessionStatus.failed;
      _error = previewMode
          ? 'Il provider IPTV non consente più connessioni simultanee.'
          : 'Il server TV ha rifiutato la connessione. Verifica che non ci '
                'siano altri dispositivi collegati con lo stesso abbonamento e riprova.';
      _notify();
      return;
    }

    // Audio but no picture: the TV's hardware decoder cannot draw this
    // video (MPEG-2, interlaced 1080i...). Another address would give the
    // same codec, so go straight to mpv with FFmpeg software decoding, which
    // decodes every broadcast codec. Done once per session.
    if (reason.contains('schermo nero') &&
        !_softwareDecode &&
        (!previewMode || previewFallback)) {
      _softwareDecode = true;
      final address = _currentUrl.isEmpty ? _candidates.first : _currentUrl;
      _plan = [
        _Attempt(PlayerEngineType.mediakit, address),
        for (final u in _candidates)
          if (u != address) _Attempt(PlayerEngineType.mediakit, u),
      ];
      _attempt = 0;
      _reconnects = 0;
      _status = SessionStatus.switching;
      _notice =
          'Video non supportato dal decoder della TV. '
          'Passo alla decodifica software...';
      _notify();
      await _openAttempt(resumeAt: resumeAt);
      return;
    }

    // A stream that was already playing and dropped: reconnect the same
    // way (at most twice) before trying anything else.
    if (midPlay && _reconnects < 2 && !reason.contains('schermo nero')) {
      _reconnects++;
      _status = SessionStatus.switching;
      _notice = 'Segnale interrotto, riconnessione...';
      _notify();
      await _openAttempt(resumeAt: resumeAt);
      return;
    }

    if (_attempt < _plan.length - 1) {
      _attempt++;
      final next = _plan[_attempt];
      _status = SessionStatus.switching;
      _notice = next.engine == failed
          ? 'Provo un formato alternativo del canale...'
          : '${failed.label} non riesce a riprodurre questo flusso. '
                'Passo a ${next.engine.label}...';
      _notify();
      await _openAttempt(resumeAt: resumeAt);
      return;
    }

    await _releaseCurrent();
    if (gen != _generation || _disposed) return;
    _status = SessionStatus.failed;
    _error = reason;
    _notify();
  }

  void clearNotice() {
    if (_notice == null) return;
    _notice = null;
    _notify();
  }

  // ---- Live timeshift --------------------------------------------------
  // The delay is tracked on the wall clock (pauses add to it, rewinds add,
  // fast-forwards remove), so it stays right even when the stream clock of
  // the provider jumps. LIVE always brings it back to zero.
  static const timeshiftWindow = Duration(minutes: 30);
  Duration _shift = Duration.zero;
  DateTime? _pausedAt;
  DateTime? _liveStartedAt;
  Timer? _delayTick;

  /// Refreshes the delay label every second while behind the live point.
  void _syncDelayTick() {
    if (isBehindLive || _pausedAt != null) {
      _delayTick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!isBehindLive && _pausedAt == null) {
          _delayTick?.cancel();
          _delayTick = null;
        }
        _notify();
      });
    } else {
      _delayTick?.cancel();
      _delayTick = null;
    }
  }

  bool get canTimeshift => isLive && (_engine?.supportsTimeshift ?? false);

  /// How far behind the live point the picture is.
  Duration get liveDelay {
    if (_engine?.value.nativeLiveSeekable == true)
      return _engine?.value.nativeLiveOffset ?? Duration.zero;
    var d = _shift;
    if (_pausedAt != null) d += DateTime.now().difference(_pausedAt!);
    final cap = _maxRewind;
    if (d > cap) d = cap;
    return d.isNegative ? Duration.zero : d;
  }

  bool get isBehindLive => canTimeshift && liveDelay.inSeconds >= 3;

  Duration get _maxRewind {
    final start = _liveStartedAt;
    if (start == null) return Duration.zero;
    final elapsed = DateTime.now().difference(start);
    return elapsed < timeshiftWindow ? elapsed : timeshiftWindow;
  }

  void _foldPause() {
    if (_pausedAt == null) return;
    _shift += DateTime.now().difference(_pausedAt!);
    _pausedAt = null;
  }

  /// Rewinds (negative) or fast-forwards (positive) inside the buffer.
  Future<void> timeshiftBy(Duration offset) async {
    final engine = _engine;
    if (engine == null || !canTimeshift) return;
    if (engine.value.nativeLiveSeekable) {
      var position = engine.value.position + offset;
      if (position.isNegative) position = Duration.zero;
      if (position > engine.value.duration) position = engine.value.duration;
      await engine.seekTo(position);
      _notify();
      return;
    }
    _liveStartedAt ??= DateTime.now();
    _foldPause();
    var target = _shift - offset;
    if (target.isNegative) target = Duration.zero;
    if (target > _maxRewind) target = _maxRewind;
    final move = _shift - target; // >0 forward, <0 backward
    _shift = target;
    if (!engine.value.isPlaying) _pausedAt = DateTime.now();
    var pos = engine.value.position + move;
    if (pos.isNegative) pos = Duration.zero;
    await engine.seekTo(pos);
    _notify();
  }

  /// Jumps back to the most recent live picture.
  Future<void> goLive() async {
    final engine = _engine;
    if (engine == null) return;
    if (engine.value.nativeLiveSeekable) {
      await engine.seekToLive();
      if (!engine.value.isPlaying) await engine.play();
      _notify();
      return;
    }
    _foldPause();
    final move = _shift;
    _shift = Duration.zero;
    final buffered = engine.value.bufferedUntil;
    var pos = engine.value.position + move;
    if (buffered > engine.value.position &&
        buffered - const Duration(milliseconds: 500) > pos) {
      pos = buffered - const Duration(milliseconds: 500);
    }
    await engine.seekTo(pos);
    if (!engine.value.isPlaying) await engine.play();
    _notify();
  }

  bool _inTick = false;
  void _syncDelayTickSafe() {
    if (_inTick) return;
    _inTick = true;
    try {
      _syncDelayTick();
    } finally {
      _inTick = false;
    }
  }

  Future<void> togglePlay() async {
    final engine = _engine;
    if (engine == null) return;
    if (isLive && canTimeshift) {
      _liveStartedAt ??= DateTime.now();
      if (engine.value.isPlaying) {
        await engine.pause();
        _pausedAt = DateTime.now();
      } else {
        _foldPause();
        if (_shift > _maxRewind) _shift = _maxRewind;
        await engine.play();
      }
      _notify();
      return;
    }
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

  /// Resumes a player paused by the system (e.g. Android audio focus).
  Future<void> ensurePlaying() async {
    final engine = _engine;
    if (engine == null || _disposed) return;
    if (!engine.value.isPlaying) await engine.play();
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
    if (_disposed) return;
    if (isLive) _syncDelayTickSafe();
    notifyListeners();
  }

  @override
  void dispose() {
    _hlsWatch?.cancel();
    _disposed = true;
    _diagnosticTimer?.cancel();
    _diagnostics?.end();
    if (_diagnosticListening) LiveDiagnosticsService.instance.removeListener(_diagnosticPreference);
    _delayTick?.cancel();
    _generation++;
    unawaited(_releaseCurrent());
    super.dispose();
  }
}
