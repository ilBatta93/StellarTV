import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../models/player_settings.dart';
import 'playback_engine.dart';

class ExoEngine extends PlaybackEngine {
  ExoEngine({required String url, required PlayerSettings settings})
    : _controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        formatHint: _formatHint(url),
          httpHeaders: {
            'User-Agent': settings.userAgent.trim().isEmpty
                ? 'StellarTV/1.0'
                : settings.userAgent.trim(),
          },
        videoPlayerOptions: VideoPlayerOptions(
          allowBackgroundPlayback: settings.backgroundAudio,
          preventsDisplaySleepDuringVideoPlayback: settings.keepScreenOn,
          backBufferDurationMs: settings.backBufferSeconds * 1000,
        ),
      );

  final VideoPlayerController _controller;
  final Map<String, VideoTrack> _videoTracks = {};
  PlaybackSnapshot _value = const PlaybackSnapshot();
  bool _disposed = false;

  static VideoFormat? _formatHint(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    if (path.endsWith('.m3u8') || path.contains('.m3u8'))
      return VideoFormat.hls;
    if (path.endsWith('.mpd')) return VideoFormat.dash;
    if (path.contains('.ism')) return VideoFormat.ss;
    return null;
  }

  @override
  PlayerEngineType get type => PlayerEngineType.exo;

  @override
  PlaybackSnapshot get value => _value;

  @override
  bool get supportsAudioTracks => _controller.isAudioTrackSupportAvailable();

  @override
  bool get supportsSubtitleTracks => false;

  @override
  bool get supportsQualitySelection =>
      _controller.isVideoTrackSupportAvailable();

  @override
  bool get supportsDelays => false;

  void _sync() {
    if (_disposed) return;
    final v = _controller.value;
    final buffered = v.buffered.isEmpty ? Duration.zero : v.buffered.last.end;
    _value = PlaybackSnapshot(
      isReady: v.isInitialized,
      isPlaying: v.isPlaying,
      isBuffering: v.isBuffering,
      isEnded: v.isCompleted,
      position: v.position,
      duration: v.duration,
      bufferedUntil: buffered,
      size: v.size,
      speed: v.playbackSpeed,
      error: v.errorDescription,
      caption: v.caption.text,
    );
    notifyListeners();
  }

  @override
  Future<void> open() async {
    _controller.addListener(_sync);
    try {
      await _controller.initialize();
    } catch (e) {
      throw PlaybackException(_describeInitError(e));
    }
    if (_controller.value.hasError) {
      throw PlaybackException(
        _controller.value.errorDescription ?? 'Errore di inizializzazione',
      );
    }
    try {
      await _controller.play();
    } catch (e) {
      throw PlaybackException(_describeInitError(e));
    }
    _sync();
  }

  /// Platform init errors are often opaque (Future timeouts, generic Platform
  /// exceptions); describe them so the fallback engine choice makes sense.
  String _describeInitError(Object e) {
    final raw = e.toString();
    if (raw.contains('TimeoutException')) {
      return 'Il flusso non risponde (timeout)';
    }
    final described = _controller.value.errorDescription;
    if (described != null && described.isNotEmpty) return described;
    return raw.isEmpty ? 'Errore di inizializzazione' : raw;
  }

  @override
  Widget buildView(double boxRatio) => VideoPlayer(_controller);

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seekTo(Duration position) => _controller.seekTo(position);

  @override
  Future<void> setSpeed(double speed) => _controller.setPlaybackSpeed(speed);

  @override
  Future<void> setVolume(double volume) =>
      _controller.setVolume(volume.clamp(0.0, 1.0));

  @override
  Future<void> applyFitMode(VideoFitMode mode, double boxRatio) async {}

  @override
  Future<List<MediaTrack>> getAudioTracks() async {
    if (!supportsAudioTracks) return const [];
    final tracks = await _controller.getAudioTracks();
    return [
      for (final t in tracks)
        MediaTrack(
          id: t.id,
          label: (t.label?.isNotEmpty ?? false)
              ? t.label!
              : languageName(t.language),
          language: t.language,
          detail: describeAudio(
            codec: t.codec,
            channels: t.channelCount,
            bitrate: t.bitrate,
          ),
          selected: t.isSelected,
        ),
    ];
  }

  @override
  Future<void> selectAudioTrack(MediaTrack track) =>
      _controller.selectAudioTrack(track.id);

  @override
  Future<List<MediaTrack>> getSubtitleTracks() async => const [];

  @override
  Future<void> selectSubtitleTrack(MediaTrack? track) async {}

  @override
  Future<List<MediaTrack>> getQualityTracks() async {
    if (!supportsQualitySelection) return const [];
    final tracks = await _controller.getVideoTracks();
    _videoTracks
      ..clear()
      ..addEntries(tracks.map((t) => MapEntry(t.id, t)));
    final sorted = [...tracks]
      ..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
    return [
      for (final t in sorted)
        MediaTrack(
          id: t.id,
          label: t.height != null
              ? '${t.height}p'
              : (t.label?.isNotEmpty ?? false)
              ? t.label!
              : 'Traccia ${t.id}',
          detail: describeVideo(
            codec: t.codec,
            bitrate: t.bitrate,
            frameRate: t.frameRate,
          ),
          selected: t.isSelected,
        ),
    ];
  }

  @override
  Future<void> selectQualityTrack(MediaTrack? track) => _controller
      .selectVideoTrack(track == null ? null : _videoTracks[track.id]);

  @override
  Future<void> setSubtitleDelay(Duration delay) async {}

  @override
  Future<void> setAudioDelay(Duration delay) async {}

  @override
  void dispose() {
    _disposed = true;
    _controller.removeListener(_sync);
    _controller.dispose();
    super.dispose();
  }
}
