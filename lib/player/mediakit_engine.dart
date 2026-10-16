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
    this.previewMode = false,
  }) : _settings = settings,
       _player = Player(
         configuration: PlayerConfiguration(
           // The old value (network caching ms * 1 KB, ~1.5 MB) held about a
           // second of HD video: any network hiccup stuttered. 32 MB minimum.
           bufferSize: previewMode
               ? 8 * 1024 * 1024
               : _bufferBytes(settings, isLive),
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
      // Fire TV stuttered with a 3 s read-ahead on live: a deeper window
      // absorbs provider jitter; previews stay short to start quickly.
      'demuxer-readahead-secs': previewMode
          ? '1'
          : isLive
          ? (DeviceTypeService.isFireTv ? '6' : '3')
          : '20',
      'vd-lavc-fast': DeviceTypeService.isFireTv ? 'yes' : 'no',
      'audio-buffer': isLive ? '0.5' : '0.2',
      'framedrop': _settings.dropLateFrames ? 'vo' : 'no',
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
  final bool previewMode;
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
  bool get supportsTimeshift => isLive && !previewMode;

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
      // Keep the rewind feature, but bound RAM on memory-constrained Fire TV.
      'demuxer-max-back-bytes':
          '${DeviceTypeService.isFireTv ? 64 * 1024 * 1024 : timeshiftBackBytes}',
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

  /// IPTV/Xtream network and demuxer options for every device: reconnects
  /// on drops, tolerates corrupt MPEG-TS packets and probes long enough to
  /// find the video stream (a short probe was a cause of audio with a
  /// black picture on live channels).
  Future<void> _tuneNetwork(String ua) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    final options = {
      'user-agent': ua,
      'network-timeout': '20',
      'tls-verify': 'no',
      'stream-lavf-o':
          'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,'
          'reconnect_delay_max=5',
      'demuxer-lavf-o': 'fflags=+discardcorrupt+genpts',
      'demuxer-lavf-probesize': isLive ? '5000000' : '10000000',
      'demuxer-lavf-analyzeduration': isLive ? '3' : '5',
      'demuxer-lavf-probe-info': 'auto',
      'hls-bitrate': 'max',
      'vd-lavc-dr': 'yes',
      'hwdec': _hwdec(_settings.hardwareDecoding),
      'hwdec-codecs': 'all',
      if (isLive)
        'demuxer-max-bytes': '${DeviceTypeService.isFireTv ? 48 : 96}MiB',
    };
    for (final entry in options.entries) {
      try {
        await platform.setProperty(entry.key, entry.value);
      } catch (_) {}
    }
  }

  /// "mediacodec" (zero-copy) renders black on several Fire TV/Android TV
  /// GPUs with live MPEG-TS; the copy variant keeps hardware decoding but
  /// always reaches the screen.
  static String _hwdec(HardwareDecoding mode) => switch (mode) {
    HardwareDecoding.disabled => 'no',
    HardwareDecoding.full => 'mediacodec,mediacodec-copy,auto-safe',
    _ => 'mediacodec-copy,auto-safe',
  };

  Timer? _blackWatch;
  int _blackStage = 0;

  /// Audio playing but no video frame size after a few seconds = black
  /// screen: switch decoder (copy hardware → software) instead of leaving
  /// the viewer in front of a black picture.
  void _watchBlackScreen() {
    _blackWatch?.cancel();
    _blackWatch = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (_disposed) return _blackWatch?.cancel();
      final st = _player.state;
      final hasVideoTrack = st.tracks.video.any(
        (t) => t.id != 'auto' && t.id != 'no',
      );
      final hasFrame = (st.width ?? 0) > 0 && (st.height ?? 0) > 0;
      if (hasFrame || !hasVideoTrack) {
        if (hasFrame) _blackWatch?.cancel();
        return;
      }
      if (!st.playing || st.position <= const Duration(seconds: 2)) return;
      final platform = _player.platform;
      if (platform is! NativePlayer || _blackStage >= 2) {
        _blackWatch?.cancel();
        return;
      }
      _blackStage++;
      try {
        await platform.setProperty(
          'hwdec',
          _blackStage == 1 ? 'mediacodec-copy' : 'no',
        );
        if (_blackStage == 2) {
          await platform.setProperty('vd-lavc-fast', 'yes');
          await platform.setProperty('vd-lavc-skiploopfilter', 'nonkey');
        }
      } catch (_) {}
    });
  }

  @override
  Future<void> open({double initialVolume = 1}) async {
    final configuredUa = _settings.userAgent.trim();
    await _tuneNetwork(configuredUa.isEmpty ? 'StellarTV/1.0' : configuredUa);
    if (DeviceTypeService.isTv) await _tuneForTv();
    if (isLive && !previewMode) await _enableTimeshift();
    await _player.setVolume(initialVolume.clamp(0.0, 1.0) * 100);
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
    _watchBlackScreen();
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
    _blackWatch?.cancel();
    await _player.dispose();
    super.dispose();
  }
}
