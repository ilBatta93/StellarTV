import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/player_settings.dart';
import 'playback_engine.dart';

/// mpv-backed engine (media_kit): full subtitle and multi-audio-track
/// support for IPTV streams, far more tolerant than the old VLC engine.
class MediaKitEngine extends PlaybackEngine {
  MediaKitEngine({required String url, required PlayerSettings settings})
      : _url = url,
        _settings = settings,
        _player = Player(
          configuration: PlayerConfiguration(
            bufferSize: settings.networkCachingMs * 1024,
            logLevel: MPVLogLevel.warn,
          ),
        ) {
    _videoController = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: settings.hardwareDecoding != HardwareDecoding.disabled,
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

  final PlayerSettings _settings;
  final String _url;
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
    _playing = Completer<void>();
    try {
      final ua = _settings.userAgent.trim();
      await _player.open(
        Media(
          _urlWithUserAgent(ua),
          httpHeaders: ua.isEmpty ? const {} : {'User-Agent': ua},
        ),
        play: true,
      );
    } catch (e) {
      throw PlaybackException('$e');
    }
    await _player.setRate(_settings.defaultSpeed);
    await _playing!.future.timeout(
      Duration(seconds: _settings.startTimeoutSeconds + 5),
      onTimeout: () => throw const PlaybackException(
          'Il flusso non risponde (timeout)'),
    );
  }

  String _urlWithUserAgent(String ua) => _url; // media_kit uses httpHeaders.

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
                codec: t.codec, channels: t.channelscount, bitrate: null),
            selected: t.id == selected?.id,
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
            selected: t.id == selected?.id,
          ),
    ];
  }

  @override
  Future<void> selectSubtitleTrack(MediaTrack? track) => _player.setSubtitleTrack(
      track == null
          ? const SubtitleTrack.no()
          : SubtitleTrack(track.id, track.label, track.language));

  @override
  Future<List<MediaTrack>> getQualityTracks() async => const [];

  @override
  Future<void> selectQualityTrack(MediaTrack? track) async {}

  @override
  Future<void> setSubtitleDelay(Duration delay) =>
      _player.platform.setSubtitleDelay(delay);

  @override
  Future<void> setAudioDelay(Duration delay) =>
      _player.platform.setAudioDelay(delay);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _player.dispose();
    super.dispose();
  }
}
