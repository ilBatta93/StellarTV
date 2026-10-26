import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import '../models/player_settings.dart';
import 'decoder_memory.dart';
import '../services/playback_work_policy.dart';
import '../services/stream_probe.dart';
import '../services/live_diagnostics_service.dart';
import '../services/live_diagnostics_tracker.dart';
import '../services/live_diagnostics_log.dart';
import '../services/vod_diagnostics_log.dart';
import '../services/vod_diagnostics_service.dart';
import '../services/vod_diagnostics_tracker.dart';

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
    this.onPositionCommitted,
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
  final Future<void> Function(Duration position)? onPositionCommitted;

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
    // Native MPEG-TS first, like the reference IPTV players. Xtream HLS is
    // produced on demand by the server: restreamed channels answered the
    // playlist at once but never delivered a picture, and every HLS session
    // stays counted by the provider after the player closes, so zapping and
    // the Diretta preview used up single-connection lines (HTTP 503). A TS
    // connection is freed as soon as its socket closes. HLS stays as the
    // fallback; the stored address (built as .m3u8) is never tried first.
    final original = url.trim();
    return switch (format) {
      LiveStreamFormat.ts ||
      LiveStreamFormat.auto => {'$base.ts', '$base.m3u8', original}.toList(),
      LiveStreamFormat.m3u8 => {'$base.m3u8', '$base.ts', original}.toList(),
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
  final Set<String> _probedFormats = {};

  /// Which player identity the server saw, as a fixed label (never the text).
  String get _uaLabel {
    final ua = effectiveStreamUserAgent(settings.userAgent);
    if (ua == kDefaultStreamUserAgent) return 'vlc';
    if (ua.toLowerCase().startsWith('okhttp')) return 'android';
    if (ua.toLowerCase().contains('smarters')) return 'smarters';
    return 'custom';
  }

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
  bool externalSubtitlesActive = false;
  bool _subtitleSelectionExplicit = false;
  MediaTrack? _selectedSubtitle;
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
  VodDiagnosticsTracker? _vod;
  Timer? _diagnosticTimer;
  bool _diagnosticListening = false;
  bool _diagnosticEnabled = false;

  /// The record this session belongs to: channels write the live one, film
  /// and series their own, so the two reports never mix.
  ChangeNotifier get _diagnosticService =>
      isLive ? LiveDiagnosticsService.instance : VodDiagnosticsService.instance;

  bool get _diagnosticsEnabled => isLive
      ? LiveDiagnosticsService.instance.enabled
      : VodDiagnosticsService.instance.enabled;

  void _diagnosticPreference() {
    if (_disposed) return;
    final enabled = _diagnosticsEnabled;
    if (enabled == _diagnosticEnabled) return;
    _diagnosticEnabled = enabled;
    if (!enabled) {
      _diagnosticTimer?.cancel();
      _diagnosticTimer = null;
      _diagnostics = null;
      _vod = null;
      return;
    }
    _diagnostics ??= isLive ? LiveDiagnosticsTracker() : null;
    _vod ??= isLive ? null : VodDiagnosticsTracker();
    final current = _engine;
    if (current != null) {
      _diagnostics?.begin(
        currentUrl,
        current.type.name,
        previewMode,
        _softwareDecode,
        observed: true,
      );
      _vod?.begin(
        currentUrl,
        current.type.name,
        previewMode,
        _softwareDecode,
        observed: true,
      );
    }
    _diagnosticTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final engine = _engine;
      if (engine == null) return;
      _diagnostics?.sample(engine);
      _vod?.sample(engine);
    });
  }

  bool _cloudPaused = false;

  Future<void> start() async {
    if (_disposed || _streamStopped) return;
    PlaybackWorkPolicy.instance.update(this, cloudBlocked: true);
    if (!_diagnosticListening) {
      _diagnosticListening = true;
      _diagnosticService.addListener(_diagnosticPreference);
      unawaited(
        isLive
            ? LiveDiagnosticsService.instance.initialize()
            : VodDiagnosticsService.instance.initialize(),
      );
      _diagnosticPreference();
    }

    if (isLive) {
      try {
        await DecoderMemory.ensureLoaded();
      } catch (_) {}
      if (_disposed) return;
      // Software decoding is a decoder choice, not an engine switch: it
      // stays available even when automatic engine fallback is off.
      if ((!previewMode || previewFallback) && DecoderMemory.needsSoftware(url))
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
          isLive: isLive,
        ),
        PlayerEngineType.mediakit => MediaKitEngine(
          url: address,
          settings: settings,
          isLive: isLive,
          previewMode: previewMode,
          softwareDecode: _softwareDecode,
          hardwareCopy: _phoneHardwareCopy,
        ),
      };

  /// Detaches the current player, unmounts its view and releases it
  /// completely (decoder, surface and provider connection) before the
  /// returned future completes. Releases are serialized.
  Future<void> _releaseCurrent() {
    final old = _engine;
    _firstPictureTimer?.cancel();
    _phoneCopyTimer?.cancel();
    if (old == null) return _releasing;
    _diagnostics?.end();
    _vod?.end();
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
    await _releaseCurrent();
    if (gen != _generation || _disposed || _plan.isEmpty) return;
    final attempt = _plan[_attempt.clamp(0, _plan.length - 1)];
    _diagnostics?.begin(
      attempt.url,
      attempt.engine.name,
      previewMode,
      _softwareDecode,
      userAgent: _uaLabel,
    );
    _vod?.begin(
      attempt.url,
      attempt.engine.name,
      previewMode,
      _softwareDecode,
      userAgent: _uaLabel,
    );

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
      await _handleFailure(
        gen,
        engine.value.error ?? 'Errore video',
        resumeAt,
        midPlay: false,
      );
      return;
    }
    _diagnostics?.event('open_ready');
    _status = SessionStatus.playing;
    _notice = null;
    // Fresh stream (new channel or reconnect): timeshift starts from here.
    _shift = Duration.zero;
    _pausedAt = null;
    _liveStartedAt = isLive ? DateTime.now() : null;
    _playingSince = DateTime.now();
    _watchFirstPicture(engine, gen);
    _watchPhoneHardwareCopy(engine, gen);
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
        if (externalSubtitlesActive || _subtitleSelectionExplicit) {
          await engine.selectSubtitleTrack(
            externalSubtitlesActive ? null : _selectedSubtitle,
          );
        } else if (!settings.subtitlesEnabled) {
          await engine.selectSubtitleTrack(null);
        } else {
          final subs = await engine.getSubtitleTracks();
          final preferred = subs
              .where(
                (t) =>
                    trackMatchesLanguage(t, settings.preferredSubtitleLanguage),
              )
              .firstOrNull;
          if (externalSubtitlesActive || _subtitleSelectionExplicit) {
            await engine.selectSubtitleTrack(
              externalSubtitlesActive ? null : _selectedSubtitle,
            );
          } else {
            await engine.selectSubtitleTrack(preferred);
          }
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
      _handleFailure(_generation, engine.value.error!, resumeAt, midPlay: true);
      return;
    }
    if (engine.value.size != _lastVideoSize) {
      _lastVideoSize = engine.value.size;
      engine.applyFitMode(fitMode, _boxRatio);
    }
    _notify();
  }

  /// How long a live player may stay "ready" without drawing its first
  /// picture. ExoPlayer is ready only with media buffered, so a picture
  /// follows within ~1-3 s on every working channel (TCL logs); mpv reports
  /// ready earlier and gets more time. The removed 3.5 s HLS check also
  /// fired while buffering; this one only ends players that never drew.
  @visibleForTesting
  static Duration firstPictureDeadline(PlayerEngineType engine) =>
      engine == PlayerEngineType.exo
      ? const Duration(seconds: 8)
      : const Duration(seconds: 14);

  /// Picks the failure for a live player that never drew a picture: media
  /// advancing (sound) means the decoder cannot draw this video; a stalled
  /// clock means the server answered but never sent the stream.
  @visibleForTesting
  static String noPictureReason({required bool mediaAdvancing}) =>
      mediaAdvancing
      ? 'Nessuna immagine dal flusso (schermo nero)'
      : 'Nessun video dal server per questo canale';

  Timer? _firstPictureTimer;
  Timer? _phoneCopyTimer;
  bool _phoneHardwareCopy = false;

  /// Black screens of the TCL logs: the player opened in ~0.4 s, then
  /// buffered forever without a frame. The decoder black-screen checks
  /// ignore buffering, so nothing ever moved to the other format.
  void _watchFirstPicture(PlaybackEngine engine, int gen) {
    _firstPictureTimer?.cancel();
    if (!isLive) return;
    final startPosition = engine.value.position;
    _firstPictureTimer = Timer(firstPictureDeadline(engine.type), () {
      if (_disposed || gen != _generation || _engine != engine) return;
      // Confirmed picture, or a platform without renderer telemetry.
      if (engine.videoFrameRendered != false || engine.audioOnly) return;
      final v = engine.value;
      final advancing =
          v.isPlaying &&
          !v.isBuffering &&
          v.position > startPosition + const Duration(seconds: 2);
      unawaited(
        _handleFailure(
          gen,
          noPictureReason(mediaAdvancing: advancing),
          null,
          midPlay: false,
        ),
      );
    });
  }

  /// iPhone film/series: zero-copy VideoToolbox, then the copy decoder if
  /// the first picture never arrives. Live and TV keep their own paths.
  void _watchPhoneHardwareCopy(PlaybackEngine engine, int gen) {
    _phoneCopyTimer?.cancel();
    if (_phoneHardwareCopy || engine is! MediaKitEngine) return;
    if (!engine.canRetryHardwareCopy) return;
    _phoneCopyTimer = Timer(firstPictureDeadline(engine.type), () {
      if (_disposed || gen != _generation || _engine != engine) return;
      if (engine.videoFrameRendered != false || engine.audioOnly) return;
      final position = engine.value.position;
      unawaited(
        _retryPhoneHardwareCopy(
          gen,
          position > Duration.zero ? position : startAt,
        ),
      );
    });
  }

  Future<void> _retryPhoneHardwareCopy(int gen, Duration? resumeAt) async {
    if (_disposed || gen != _generation || _phoneHardwareCopy) return;
    _phoneHardwareCopy = true;
    _phoneCopyTimer?.cancel();
    _status = SessionStatus.switching;
    _notice = null;
    _notify();
    await _releaseCurrent();
    if (_disposed || gen != _generation) return;
    await _openAttempt(resumeAt: resumeAt);
  }

  /// Pause before reopening a live channel that dropped mid-play.
  @visibleForTesting
  static Duration liveReconnectDelay(int reconnect) =>
      Duration(milliseconds: 1200 * reconnect.clamp(1, 3));

  /// Pause before trying another address of the same live channel.
  @visibleForTesting
  static const liveFormatSwitchDelay = Duration(milliseconds: 1200);

  static bool _isServerRefusal(String reason) {
    final lower = reason.toLowerCase();
    return lower.contains('458') ||
        lower.contains('-16845') ||
        lower.contains('http 403') ||
        lower.contains('forbidden') ||
        lower.contains('429') ||
        lower.contains('503') ||
        lower.contains('service unavailable') ||
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
    // A live channel paused by the viewer: providers often drop the idle
    // connection, and reconnecting at once restarted the picture by itself.
    // Keep the pause; the stream reopens at LIVE when the viewer resumes.
    if (isLive && _userPausedLive) {
      _deferredLiveFailure = true;
      _notify();
      return;
    }
    final status = StreamProbe.statusIn(reason);
    _diagnostics?.event(
      'error',
      data: {
        'category': LiveDiagnosticsLog.errorKind(reason),
        'midPlay': midPlay,
        if (status != null) 'httpStatus': status,
      },
    );
    _vod?.event(
      'error',
      data: {
        'category': VodDiagnosticsLog.errorKind(reason),
        'midPlay': midPlay,
        if (status != null) 'httpStatus': status,
      },
    );

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
      // HTTP 503 from a load-balanced sub-server can be a single format
      // being unavailable: try the remaining addresses before giving up.
      final unavailable =
          reason.contains('503') ||
          reason.toLowerCase().contains('service unavailable');
      if (unavailable && _attempt < _plan.length - 1) {
        _serverRefusalRetries = 0;
        _attempt++;
        _status = SessionStatus.switching;
        _notice = 'Provo un formato alternativo del canale...';
        _notify();
        await _releaseCurrent();
        await Future<void>.delayed(liveFormatSwitchDelay);
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
      // Back off before reconnecting: an immediate reopen hit the provider
      // while it still counted the dropped connection.
      if (isLive) {
        await _releaseCurrent();
        await Future<void>.delayed(liveReconnectDelay(_reconnects));
        if (_disposed || gen != _generation) return;
      }
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
      // A different address of the same channel (HLS -> MPEG-TS) is a new
      // provider session: let the server drop the previous one first.
      if (isLive && next.url != _currentUrl) {
        await _releaseCurrent();
        await Future<void>.delayed(liveFormatSwitchDelay);
        if (_disposed || gen != _generation) return;
      }
      await _openAttempt(resumeAt: resumeAt);
      return;
    }

    await _releaseCurrent();
    if (gen != _generation || _disposed) return;
    // Opt-in diagnostics: only once every attempt has failed and the
    // player is released. Probing between attempts opened an extra provider
    // connection right before the next player (single-connection lines then
    // refused or starved the retry).
    final tracker = _diagnostics;
    final fmt = Uri.tryParse(_currentUrl)?.path.split('.').last ?? '';
    if (tracker != null &&
        isLive &&
        !previewMode &&
        !tracker.firstFrame &&
        _currentUrl.isNotEmpty &&
        _probedFormats.add(fmt)) {
      try {
        final r = await StreamProbe.run(
          _currentUrl,
          effectiveStreamUserAgent(settings.userAgent),
        ).timeout(const Duration(seconds: 9));
        tracker.event('stream_probe', data: r);
      } catch (_) {}
    }
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
    if (_deferredLiveFailure) return _resumeDeferredLive();
    _userPausedLive = false;
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

  bool _userPausedLive = false;
  bool _deferredLiveFailure = false;

  /// True while a paused live channel waits to reopen at LIVE.
  bool get liveResumePending => _deferredLiveFailure;

  Future<void> _resumeDeferredLive() async {
    _deferredLiveFailure = false;
    _userPausedLive = false;
    _shift = Duration.zero;
    _pausedAt = null;
    await retry();
  }

  Future<void> togglePlay() async {
    final engine = _engine;
    if (engine == null) return;
    if (isLive && _deferredLiveFailure) {
      _cloudPaused = false;
      PlaybackWorkPolicy.instance.update(this, cloudBlocked: true);
      return _resumeDeferredLive();
    }
    final pausing = engine.value.isPlaying;
    if (!pausing) {
      _cloudPaused = false;
      PlaybackWorkPolicy.instance.update(this, cloudBlocked: true);
    }
    if (isLive) {
      _userPausedLive = engine.value.isPlaying;
      if (_userPausedLive) {
        _firstPictureTimer?.cancel();
      } else {
        _watchFirstPicture(engine, _generation);
      }
    }
    if (isLive && canTimeshift) {
      _liveStartedAt ??= DateTime.now();
      if (engine.value.isPlaying) {
        await engine.pause();
        _cloudPaused = true;
        PlaybackWorkPolicy.instance.update(this, cloudBlocked: false);
        _pausedAt = DateTime.now();
      } else {
        _foldPause();
        if (_shift > _maxRewind) _shift = _maxRewind;
        await engine.play();
      }
      _notify();
      return;
    }
    if (!isLive && engine.value.isEnded) {
      await engine.seekTo(Duration.zero);
      await onPositionCommitted?.call(Duration.zero);
      _vod?.markSeek();
      await engine.play();
    } else if (engine.value.isPlaying) {
      await engine.pause();
      _cloudPaused = true;
      PlaybackWorkPolicy.instance.update(this, cloudBlocked: false);
    } else {
      await engine.play();
    }
    _notify();
  }

  int _seekRevision = 0;
  Future<void> seekTo(Duration position) async {
    final revision = ++_seekRevision;
    final engine = _engine;
    if (engine == null || isLive) return;
    final max = engine.value.duration;
    var target = position < Duration.zero ? Duration.zero : position;
    if (max > Duration.zero && target > max) target = max;
    await engine.seekTo(target);
    if (_engine != engine || revision != _seekRevision) return;
    await onPositionCommitted?.call(target);
    // The viewer moved the position: the next sample is not a stutter.
    _vod?.markSeek();
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
    if (engine == null || _disposed || (isLive && _userPausedLive)) return;
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

  Future<void> setExternalSubtitles(bool active) async {
    externalSubtitlesActive = active;
    _subtitleSelectionExplicit = true;
    _selectedSubtitle = null;
    if (active) await _engine?.selectSubtitleTrack(null);
    _notify();
  }

  Future<List<MediaTrack>> subtitleTracks() async {
    final engine = _engine;
    if (engine == null || !engine.supportsSubtitleTracks) return const [];
    return engine.getSubtitleTracks();
  }

  Future<void> selectSubtitleTrack(MediaTrack? track) async {
    externalSubtitlesActive = false;
    _subtitleSelectionExplicit = true;
    _selectedSubtitle = track;
    await _engine?.selectSubtitleTrack(track);
    _notify();
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
    if (!_streamStopped) {
      PlaybackWorkPolicy.instance.update(
        this,
        cloudBlocked: !_cloudPaused && !value.isEnded,
      );
    }
    notifyListeners();
  }

  bool _streamStopped = false;
  bool get streamStopped => _streamStopped;

  /// Closes the provider connection at once (TV off, app in background),
  /// without waiting for the widget tree: background apps draw no frames, so
  /// waiting for dispose would keep the stream open while nobody watches.
  /// Aborts any pending open or retry. Safe to call more than once.
  void stopStream() {
    if (_disposed || _streamStopped) return;
    _streamStopped = true;
    _firstPictureTimer?.cancel();
    _phoneCopyTimer?.cancel();
    _diagnosticTimer?.cancel();
    _delayTick?.cancel();
    _generation++;
    unawaited(
      _releaseCurrent().whenComplete(() {
        PlaybackWorkPolicy.instance.remove(this);
      }),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _firstPictureTimer?.cancel();
    _phoneCopyTimer?.cancel();
    _diagnosticTimer?.cancel();
    _diagnostics?.end();
    _vod?.end();
    if (_diagnosticListening)
      _diagnosticService.removeListener(_diagnosticPreference);

    _delayTick?.cancel();
    _generation++;
    unawaited(
      _releaseCurrent().whenComplete(() {
        PlaybackWorkPolicy.instance.remove(this);
      }),
    );
    super.dispose();
  }
}
