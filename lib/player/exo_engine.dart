import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../models/player_settings.dart';
import 'playback_engine.dart';

class ExoEngine extends PlaybackEngine {
  /// [shared] is for MultiView and the Live preview: several players run at
  /// once, so this one must not take Android's audio focus (which pauses
  /// every other ExoPlayer).
  ExoEngine({
    required String url,
    required PlayerSettings settings,
    bool shared = false,
    this.isLive = false,
  }) : _mediaUrl = url,
       _controller = VideoPlayerController.networkUrl(
         Uri.parse(url),
         formatHint: _formatHint(url),
         httpHeaders: _streamHeaders(settings, shared: shared, live: isLive),
         videoPlayerOptions: VideoPlayerOptions(
           // Without this every new player steals the audio focus and
           // Android pauses the others: the MultiView tiles froze.
           mixWithOthers: shared,
           allowBackgroundPlayback: settings.backgroundAudio,
           preventsDisplaySleepDuringVideoPlayback: settings.keepScreenOn,
           backBufferDurationMs: shared ? 0 : (isLive ? 60000 : settings.backBufferSeconds * 1000),
         ),
         // Texture on every device. The native-surface (platform view) mode
         // showed a black picture and crashed when released/clipped on Fire
         // TV, Google TV and Chromecast, especially with live channels.
         viewType: VideoViewType.textureView,
       );

  final bool isLive;
  String _mediaUrl;
  final VideoPlayerController _controller;

  /// Android-only. Other platforms must not receive this header: they would
  /// forward it to the stream. The Android player removes it before the request.
  static Map<String, String> _streamHeaders(
    PlayerSettings settings, {
    required bool shared,
    required bool live,
  }) {
    final headers = <String, String>{
      'User-Agent': effectiveStreamUserAgent(settings.userAgent),
    };
    if (defaultTargetPlatform == TargetPlatform.android) {
      headers[exoLoadControlHeader] = ExoLoadProfile.forPlayback(
        preview: shared,
        live: live,
        backBufferMs: shared ? 0 : (live ? 60000 : settings.backBufferSeconds * 1000),
      ).wire;
    }
    return headers;
  }
  final Map<String, VideoTrack> _videoTracks = {};
  PlaybackSnapshot _value = const PlaybackSnapshot();
  bool _disposed = false;
  Timer? _livePoll;
  Map<Object?, Object?> _window = const {};
  bool _polling = false;
  int? _playerId;

  MethodChannel get _liveChannel {
    // _playerId is set in open() after initialize(); avoid direct access to
    // the restricted controller.playerId member outside video_player package.
    return MethodChannel(
      // ignore: invalid_use_of_visible_for_testing_member
      'stellartv/video_player_android/live/${_playerId ?? _controller.playerId}',
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
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
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

  @override
  int? get renderedFrameCount {
    final rendered = _window['renderedFrames'];
    if (rendered is num) return rendered.toInt();
    return null;
  }

  /// Opt-in diagnostics: how much film is already in the player buffer.
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
      isEnded: !isLive && v.isCompleted,
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
      // ignore: invalid_use_of_visible_for_testing_member
      _playerId = _controller.playerId; // memorizza per _liveChannel
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
    // ignore: invalid_use_of_visible_for_testing_member
    _playerId = _controller.playerId; // assicurati di avere un id valido per liveChannel
    _livePoll = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _pollWindow(),
    );
  }

  @override
  Future<void> sampleOutput() => _pollWindow();

  @override
  Future<bool> reopen(String url) async {
    if (_disposed) return false;
    final hint = _formatHint(url);
    if (hint != _formatHint(_mediaUrl)) return false;
    final mime = switch (hint) {
      VideoFormat.hls => 'application/x-mpegURL',
      VideoFormat.dash => 'application/dash+xml',
      VideoFormat.ss => 'application/vnd.ms-sstr+xml',
      _ => null,
    };
    try {
      final ok = await _liveChannel.invokeMethod<bool>('replaceMedia', {
        'uri': url,
        'mime': mime,
      });
      if (ok != true || _disposed) return false;
      _mediaUrl = url;
      _blackError = null;
      _window = const {'firstFrameRendered': false};
      _sync();
      return true;
    } catch (_) {
      return false;
    }
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

/// Same wire format as the Android player header parser.
const exoLoadControlHeader = 'X-StellarTV-LoadControl';

/// Forward buffer for one ExoPlayer. Preview and MultiView stay short so four
/// tiles do not each keep a film-sized buffer. Live keeps its back buffer only
/// when the native window is seekable.
class ExoLoadProfile {
  const ExoLoadProfile({
    required this.minBufferMs,
    required this.maxBufferMs,
    required this.bufferForPlaybackMs,
    required this.bufferForPlaybackAfterRebufferMs,
    required this.backBufferMs,
    required this.backBufferRequiresSeekable,
    required this.targetBufferBytes,
  });

  static const previewTargetBytes = 8 * 1024 * 1024;

    final back = backBufferMs < 0 ? 0 : backBufferMs;
    if (preview) {
      return const ExoLoadProfile(
        minBufferMs: 1500,
        maxBufferMs: 4000,
        bufferForPlaybackMs: 500,
        bufferForPlaybackAfterRebufferMs: 1000,
        backBufferMs: 0,
        backBufferRequiresSeekable: false,
        targetBufferBytes: previewTargetBytes,
      );
    }
    if (live) {
      // Stay near the live edge. A multi-second floor paused the picture
      // for the whole rebuffer wait whenever the buffer dipped.
      // maxBuffer 12 s absorbs provider jitter; rebuffer threshold 2 s is
      // enough to catch a keyframe without raising first-frame latency.
      return ExoLoadProfile(
        minBufferMs: 800,
        maxBufferMs: 12000,
        bufferForPlaybackMs: 400,
        bufferForPlaybackAfterRebufferMs: 2000,
        backBufferMs: back,
        backBufferRequiresSeekable: true,
        targetBufferBytes: 0,
      );
    }
    return ExoLoadProfile(
      minBufferMs: 15000,
      maxBufferMs: 50000,
      bufferForPlaybackMs: 2500,
      bufferForPlaybackAfterRebufferMs: 5000,
      backBufferMs: back,
      backBufferRequiresSeekable: false,
      targetBufferBytes: 0,
    );
  }

  final int minBufferMs;
  final int maxBufferMs;
  final int bufferForPlaybackMs;
  final int bufferForPlaybackAfterRebufferMs;
  final int backBufferMs;
  final bool backBufferRequiresSeekable;
  final int targetBufferBytes;

  String get wire =>
      '$minBufferMs,$maxBufferMs,$bufferForPlaybackMs,$bufferForPlaybackAfterRebufferMs,$backBufferMs,${backBufferRequiresSeekable ? 1 : 0},$targetBufferBytes';

  static ExoLoadProfile forPlayback({
    required bool preview,
    required bool live,
    required int backBufferMs,
  }) {
    final previewTargetBytes = 8 * 1024 * 1024;
    if (preview) {
      return ExoLoadProfile(
        minBufferMs: 1500,
        maxBufferMs: 4000,
        bufferForPlaybackMs: 500,
        bufferForPlaybackAfterRebufferMs: 1000,
        backBufferMs: 0,
        backBufferRequiresSeekable: false,
        targetBufferBytes: previewTargetBytes,
      );
    }
    if (live) {
      return ExoLoadProfile(
        minBufferMs: 800,
        maxBufferMs: 12000,
        bufferForPlaybackMs: 400,
        bufferForPlaybackAfterRebufferMs: 2000,
        backBufferMs: backBufferMs,
        backBufferRequiresSeekable: true,
        targetBufferBytes: 0,
      );
    }
    return ExoLoadProfile(
      minBufferMs: 15000,
      maxBufferMs: 50000,
      bufferForPlaybackMs: 2500,
      bufferForPlaybackAfterRebufferMs: 5000,
      backBufferMs: backBufferMs,
      backBufferRequiresSeekable: false,
      targetBufferBytes: 0,
    );
  }
}
