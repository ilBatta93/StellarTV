import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/player_settings.dart';
import '../services/device_type_service.dart';
import 'playback_engine.dart';

/// mpv-backed engine (media_kit): full subtitle and multi-audio-track
/// support for IPTV streams, far more tolerant than the old VLC engine.
class MediaKitEngine extends PlaybackEngine {
  MediaKitEngine({
    required this.url,
    required PlayerSettings settings,
    this.isLive = false,
  }) : _settings = settings,
       _player = Player(
         configuration: PlayerConfiguration(
           // The old value (network caching ms * 1 KB, ~1.5 MB) held about a
           // second of HD video: any network hiccup stuttered. 32 MB minimum.
           bufferSize: _bufferBytes(settings, isLive),
           logLevel: MPVLogLevel.warn,
         ),
       ) {
    _videoController = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration:
            settings.hardwareDecoding != HardwareDecoding.disabled,
        vo: null,
      ),
    );
    _player.stream.error.listen(_onError);
    _player.stream.completed.listen(_onCompleted);
    _player.stream.playing.listen((_) => _sync());
    _player.stream.buffering.listen((_) => _sync());
    _player.stream.position.listen((_) => _sync());
    _player.stream.duration.listen((_) => _sync());
    _player.stream.track.listen((_) => _sync());
    _sync();
  }

  static int _bufferBytes(PlayerSettings settings, bool isLive) {
    const minimum = 32 * 1024 * 1024;
    final configured =
        (isLive ? settings.liveCachingMs : settings.networkCachingMs) * 1024;
    return configured < minimum ? minimum : configured;
  }

  /// TV boxes have weak GPUs: mpv's high-quality scalers and dithering
  /// dropped frames at 1080p/4K. Fast scaling looks the same at TV distance.
  /// A deeper read-ahead keeps IPTV streams smooth.
  Future<void> _tuneForTv() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    final options = {
      'scale': 'bilinear',
      'dscale': 'bilinear',
      'cscale': 'bilinear',
      'dither-depth': 'no',
      'correct-downscaling': 'no',
      'linear-downscaling': 'no',
      'sigmoid-upscaling': 'no',
      'deband': 'no',
      'interpolation': 'no',
      'video-sync': 'audio',
      'cache': 'yes',
      'demuxer-readahead-secs': isLive ? '1' : '20',
      'cache-pause-initial': 'no',
      'vd-lavc-threads': '0',
    };
    for (final entry in options.entries) {
      try {
        await platform.setProperty(entry.key, entry.value);
      } catch (_) {}
    }
  }

  final bool isLive;
  final PlayerSettings _settings;
  final String url;
  late final Player _player;
  late final VideoController _videoController;
  PlaybackSnapshot _value = const PlaybackSnapshot();
  bool _disposed = false;
  Completer<void>? _playing;

  @override
  PlayerEngineType get type => PlayerEngineType.mediakit;

  @override
  PlaybackSnapshot get value => _value;

  @override
  bool get supportsAudioTracks => true;

  @override
  bool get supportsSubtitleTracks => true;

  @override
  bool get supportsQualitySelection => false;

  @override
  bool get supportsDelays => true;

  @override
  bool get supportsTimeshift => isLive;

  /// Local timeshift window kept by mpv behind the playback point.
  static const timeshiftBackBytes = 256 * 1024 * 1024;

  /// Lets mpv keep already-played live data so the viewer can pause and
  /// rewind, and keep downloading while paused (true timeshift buffer).
  Future<void> _enableTimeshift() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    final options = {
      'cache': 'yes',
      'demuxer-seekable-cache': 'yes',
      'force-seekable': 'yes',
      'demuxer-max-back-bytes': '$timeshiftBackBytes',
      'demuxer-donate-buffer': 'no',
      'cache-pause': 'yes',
    };
    for (final entry in options.entries) {
      try {
        await platform.setProperty(entry.key, entry.value);
      } catch (_) {}
    }
  }

  void _onError(String message) {
    if (_disposed || message.isEmpty) return;
    _value = PlaybackSnapshot(
      isReady: _value.isReady,
      isPlaying: _value.isPlaying,
      isBuffering: _value.isBuffering,
      position: _value.position,
      duration: _value.duration,
      size: _value.size,
      speed: _value.speed,
      error: message,
    );
    notifyListeners();
  }

  void _onCompleted(bool completed) {
    if (!completed || _disposed) return;
    _sync();
  }

  void _sync() {
    if (_disposed) return;
    final p = _player.state;
    Size size = _value.size;
    final videoTracks = p.tracks.video;
    if (videoTracks.isNotEmpty) {
      final t = videoTracks.first;
      if (t.w != null && t.h != null) {
        size = Size(t.w!.toDouble(), t.h!.toDouble());
      }
    }
    _value = PlaybackSnapshot(
      isReady: true,
      isPlaying: p.playing,
      isBuffering: p.buffering,
      isEnded: p.completed,
      position: p.position,
      duration: p.duration,
      bufferedUntil: p.buffer,
      size: size,
      speed: p.rate,
      error: _value.hasError ? _value.error : null,
    );
    notifyListeners();
    if (_playing != null &&
        !_playing!.isCompleted &&
        (p.playing || p.position > Duration.zero)) {
      _playing!.complete();
    }
  }

  @override
  Future<void> open() async {
    if (DeviceTypeService.isTv) await _tuneForTv();
    if (isLive) await _enableTimeshift();
    _playing = Completer<void>();
    try {
      final configured = _settings.userAgent.trim();
      final ua = configured.isEmpty ? 'StellarTV/1.0' : configured;
      await _player.open(
        Media(_urlWithUserAgent(ua), httpHeaders: {'User-Agent': ua}),
        play: true,
      );
    } catch (e) {
      throw PlaybackException('$e');
    }
    await _player.setRate(isLive ? 1.0 : _settings.defaultSpeed);
    await _playing!.future.timeout(
      Duration(seconds: _settings.startTimeoutSeconds + 5),
      onTimeout: () =>
          throw const PlaybackException('Il flusso non risponde (timeout)'),
    );
  }

  String _urlWithUserAgent(String ua) => url; // media_kit uses httpHeaders.

  @override
  Widget buildView(double boxRatio) => Video(
    controller: _videoController,
    controls: NoVideoControls,
    fit: BoxFit.contain,
  );

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seekTo(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setRate(speed);

  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume((volume.clamp(0.0, 1.0) * 100));

  @override
  Future<void> applyFitMode(VideoFitMode mode, double boxRatio) async {
    // media_kit letterboxes internally; stretched modes use the surface's
    // OverflowBox sizing in VideoSurface, so no native call is required.
  }

  String _trackLabel(dynamic track, String fallback) {
    final title = track.title as String?;
    final lang = track.language as String?;
    if (title != null && title.isNotEmpty) return title;
    if (lang != null && lang.isNotEmpty) return languageName(lang);
    return fallback;
  }

  @override
  Future<List<MediaTrack>> getAudioTracks() async {
    final tracks = _player.state.tracks.audio;
    final selected = _player.state.track.audio;
    return [
      for (final (i, t) in tracks.indexed)
        if (t.id != 'auto' && t.id != 'no')
          MediaTrack(
            id: t.id,
            label: _trackLabel(t, 'Traccia audio ${i + 1}'),
            language: t.language,
            detail: describeAudio(
              codec: t.codec,
              channels: t.channelscount,
              bitrate: null,
            ),
            selected: t.id == selected.id,
          ),
    ];
  }

  @override
  Future<void> selectAudioTrack(MediaTrack track) =>
      _player.setAudioTrack(AudioTrack(track.id, track.label, track.language));

  @override
  Future<List<MediaTrack>> getSubtitleTracks() async {
    final tracks = _player.state.tracks.subtitle;
    final selected = _player.state.track.subtitle;
    return [
      for (final (i, t) in tracks.indexed)
        if (t.id != 'auto' && t.id != 'no')
          MediaTrack(
            id: t.id,
            label: _trackLabel(t, 'Sottotitolo ${i + 1}'),
            language: t.language,
            selected: t.id == selected.id,
          ),
    ];
  }

  @override
  Future<void> selectSubtitleTrack(MediaTrack? track) =>
      _player.setSubtitleTrack(
        track == null
            ? SubtitleTrack.no()
            : SubtitleTrack(track.id, track.label, track.language),
      );

  @override
  Future<List<MediaTrack>> getQualityTracks() async => const [];

  @override
  Future<void> selectQualityTrack(MediaTrack? track) async {}

  @override
  Future<void> setSubtitleDelay(Duration delay) async {
    await _setProperty('sub-delay', delay);
  }

  @override
  Future<void> setAudioDelay(Duration delay) async {
    await _setProperty('audio-delay', delay);
  }

  /// mpv expects delays in seconds (fractions allowed); harmless no-op on
  /// platforms where the native player handle is unavailable.
  Future<void> _setProperty(String name, Duration delay) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.setProperty(
        name,
        (delay.inMicroseconds / 1e6).toStringAsFixed(3),
      );
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _player.dispose();
    super.dispose();
  }
}
