import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../models/player_settings.dart';
import 'playback_engine.dart';
import 'video_health.dart';

class ExoEngine extends PlaybackEngine {
  /// [shared] is for MultiView and the Live preview: several players run at
  /// once, so this one must not take Android's audio focus (which pauses
  /// every other ExoPlayer) and reports a black picture sooner so the tile
  /// can move to mpv software decoding.
  ExoEngine({
    required String url,
    required PlayerSettings settings,
    bool shared = false,
  }) : _blackStrikes = shared ? 2 : 3,
       _controller = VideoPlayerController.networkUrl(
         Uri.parse(url),
         formatHint: _formatHint(url),
         httpHeaders: {
           'User-Agent': effectiveStreamUserAgent(settings.userAgent),
         },
         videoPlayerOptions: VideoPlayerOptions(
           // Without this every new player steals the audio focus and
           // Android pauses the others: the MultiView tiles froze.
           mixWithOthers: shared,
           allowBackgroundPlayback: settings.backgroundAudio,
           preventsDisplaySleepDuringVideoPlayback: settings.keepScreenOn,
           backBufferDurationMs: settings.backBufferSeconds * 1000,
         ),
         // Texture on every device. The native-surface (platform view) mode
         // showed a black picture and crashed when released/clipped on Fire
         // TV, Google TV and Chromecast, especially with live channels.
         viewType: VideoViewType.textureView,
       );

  final VideoPlayerController _controller;
  final int _blackStrikes;
  final Map<String, VideoTrack> _videoTracks = {};
  PlaybackSnapshot _value = const PlaybackSnapshot();
  bool _disposed = false;
  Timer? _blackWatch;
  Timer? _livePoll;
  Map<Object?, Object?> _window = const {};
  bool _polling = false;
  MethodChannel get _liveChannel {
    // The controller exposes the native player identity, distinct from texture.
    // ignore: invalid_use_of_visible_for_testing_member
    return MethodChannel(
      'stellartv/video_player_android/live/${_controller.playerId}',
    );
  }

  @override
  bool get supportsTimeshift =>
      _window['isLive'] == true &&
      _window['isSeekable'] == true &&
      (_window['durationMs'] as num? ?? 0) > 0;
  Future<void> _pollWindow() async {
    if (_disposed ||
        _polling ||
        defaultTargetPlatform != TargetPlatform.android)
      return;
    _polling = true;
    try {
      final window = await _liveChannel.invokeMapMethod<Object?, Object?>(
        'getLiveWindow',
      );
      if (_disposed) return;
      _window = window ?? const {};
      _sync();
    } catch (_) {
      /* Non-Android implementations retain their existing behavior. */
    } finally {
      _polling = false;
    }
  }

  @override
  Future<void> seekToLive() async {
    if (!supportsTimeshift) return;
    await _liveChannel.invokeMethod<bool>('seekToDefaultLivePosition');
    await _pollWindow();
  }

  String? _blackError;

  static VideoFormat? _formatHint(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    if (path.endsWith('.m3u8') || path.contains('.m3u8')) {
      return VideoFormat.hls;
    }
    if (path.endsWith('.mpd')) return VideoFormat.dash;
    if (path.contains('.ism')) return VideoFormat.ss;
    return null;
  }

  @override
  PlayerEngineType get type => PlayerEngineType.exo;

  @override
  bool? get videoFrameRendered => _window['firstFrameRendered'] as bool?;

  @override
  bool get audioOnly =>
      _window['tracksKnown'] == true && _window['hasVideoTrack'] == false;

  /// Opt-in diagnostics: how much film is already in the player buffer.
  /// ExoPlayer exposes no frame counter, so the read-ahead is the only
  /// numeric signal this engine can give.
  @override
  Future<Map<String, Object?>> metrics() async {
    if (_disposed) return const {};
    final v = _controller.value;
    if (!v.isInitialized) return const {};
    final buffered = v.buffered.isEmpty ? Duration.zero : v.buffered.last.end;
    final ahead = buffered - v.position;
    return {
      'cacheSeconds':
          (ahead < Duration.zero ? Duration.zero : ahead).inMilliseconds /
              1000.0,
    };
  }

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
      position: supportsTimeshift
          ? Duration(
              milliseconds:
                  (_window['positionMs'] as num? ?? v.position.inMilliseconds)
                      .toInt(),
            )
          : v.position,
      duration: supportsTimeshift
          ? Duration(milliseconds: (_window['durationMs'] as num).toInt())
          : v.duration,
      nativeLiveSeekable: supportsTimeshift,
      nativeLiveOffset: (_window['liveOffsetMs'] as num?) == null
          ? null
          : Duration(milliseconds: (_window['liveOffsetMs'] as num).toInt()),
      bufferedUntil: buffered,
      size: v.size,
      speed: v.playbackSpeed,
      error: _blackError ?? v.errorDescription,
      caption: v.caption.text,
    );
    notifyListeners();
  }

  @override
  Future<void> open({double initialVolume = 1}) async {
    _controller.addListener(_sync);
    try {
      await _controller.initialize();
      if (_disposed) return;
    } catch (e) {
      throw PlaybackException(_describeInitError(e));
    }
    if (_controller.value.hasError) {
      throw PlaybackException(
        _controller.value.errorDescription ?? 'Errore di inizializzazione',
      );
    }
    try {
      await _controller.setVolume(initialVolume.clamp(0.0, 1.0));
      if (_disposed) return;
      await _controller.play();
    } catch (e) {
      throw PlaybackException(_describeInitError(e));
    }
    if (_disposed) return;
    _sync();
    await _pollWindow();
    if (_disposed) return;
    _livePoll = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _pollWindow(),
    );
    _watchBlackScreen();
  }

  /// Some live streams decode audio but never produce a video frame on the
  /// texture (codec not supported by the device): the sound plays while the
  /// picture stays black. After a few seconds this reports an error so the
  /// session tries the next format or engine instead of a black screen.
  void _watchBlackScreen() {
    _blackWatch?.cancel();
    final health = VideoHealth(missingLimit: _blackStrikes);
    int? lastRendered;
    _blackWatch = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_disposed) {
        _blackWatch?.cancel();
        return;
      }
      final v = _controller.value;
      if (v.hasError || !v.isInitialized) return;
      final rendered = (_window['renderedFrames'] as num?)?.toInt();
      bool? hasFrame;
      if (_window.containsKey('firstFrameRendered')) {
        hasFrame = _window['firstFrameRendered'] == true;
        if (hasFrame && rendered != null && lastRendered != null) {
          hasFrame = rendered > (lastRendered ?? 0);
        }
      } else if (v.size.width <= 0 || v.size.height <= 0) {
        // Other native platforms do not expose output telemetry. Unknown
        // metadata must not be presented as confirmed rendered video.
        hasFrame = false;
      }
      lastRendered = rendered;
      if (health.check(
        playing: v.isPlaying,
        buffering: v.isBuffering,
        audioOnly:
            _window['tracksKnown'] == true && _window['hasVideoTrack'] == false,
        frameAvailable: hasFrame,
      )) {
        _blackWatch?.cancel();
        _blackError = 'Nessuna immagine dal flusso (schermo nero)';
        _sync();
      }
    });
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
  Future<void> seekTo(Duration position) async {
    if (!supportsTimeshift) {
      await _controller.seekTo(position);
      return;
    }
    await _liveChannel.invokeMethod<bool>('seekWithinLiveWindow', {
      'positionMs': position.inMilliseconds,
    });
    await _pollWindow();
  }

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
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _blackWatch?.cancel();
    _livePoll?.cancel();
    _controller.removeListener(_sync);
    try {
      await _controller.pause();
    } catch (_) {}
    try {
      await _controller.dispose();
    } catch (_) {}
    super.dispose();
  }
}
