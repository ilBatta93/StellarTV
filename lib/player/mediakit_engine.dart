import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/player_settings.dart';
import '../services/device_type_service.dart';
import 'playback_engine.dart';
import 'video_health.dart';

/// mpv-backed engine (media_kit): full subtitle and multi-audio-track
/// support for IPTV streams, far more tolerant than the old VLC engine.
class MediaKitEngine extends PlaybackEngine {
  MediaKitEngine({
    required this.url,
    required PlayerSettings settings,
    this.isLive = false,
    this.previewMode = false,
    this.softwareDecode = false,
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
            !softwareDecode &&
            settings.hardwareDecoding != HardwareDecoding.disabled,
        // hwdec must be given here: the controller applies its own value
        // asynchronously and silently overrode the one set at open.
        hwdec: softwareDecode ? 'no' : _hwdec(settings.hardwareDecoding),
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
    final minimum = (isLive && DeviceTypeService.isTv ? 16 : 32) * 1024 * 1024;
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
      'vd-lavc-fast': (DeviceTypeService.isFireTv || softwareDecode)
          ? 'yes'
          : 'no',
      // Software decoding of broadcast 1080i: cheap deinterlacing, skip the
      // loop filter so weak TV CPUs keep up.
      if (softwareDecode) 'deinterlace': 'yes',
      if (softwareDecode) 'vd-lavc-skiploopfilter': 'nonref',
      'audio-buffer': isLive ? '0.5' : '0.2',
      // Never drop frames on live: a jittery IPTV clock made mpv discard
      // every picture at start (audio with a black screen).
      'framedrop': (!isLive && _settings.dropLateFrames) ? 'vo' : 'no',
      // Broadcast H.264 1080i, MPEG-2 and VC-1 channels gave audio with a
      // black picture through MediaCodec on Fire TV / Google TV /
      // Chromecast (no hardware deinterlacing towards the texture). Live:
      // hardware only for the progressive 4K codecs those chips really draw
      // (HEVC/VP9/AV1, always worked); FFmpeg decodes and deinterlaces the
      // rest. Film/series (progressive H.264) keep hardware H.264.
      if (!softwareDecode)
        'hwdec-codecs': isLive ? 'hevc,vp9,av1' : 'h264,hevc,vp9,av1',
      if (isLive && !softwareDecode) 'deinterlace': 'auto',
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

  /// FFmpeg decoding on the CPU: used when the TV's hardware decoder gave
  /// audio with a black picture (MPEG-2 / interlaced broadcast channels).
  final bool softwareDecode;
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
  bool? get videoFrameRendered => _firstFrameRendered;

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
      // The seekable cache made mpv jump back into already-played data on
      // MPEG-TS timestamp resets (live replayed in a loop): keep it off and
      // let pause/rewind use the plain back buffer.
      'demuxer-seekable-cache': 'no',
      // No 'force-seekable': media_kit seeks to 0 every time the Android
      // surface is (re)attached; on a forced-seekable live stream that seek
      // jumped outside the stream (black picture, stalled player). The
      // seekable cache alone already allows pause/rewind (partially-seekable).
      // RAM is bounded on every TV (Fire TV/Chromecast have 1-2 GB).
      'demuxer-max-back-bytes':
          '${DeviceTypeService.isTv ? 32 * 1024 * 1024 : timeshiftBackBytes}',
      'demuxer-donate-buffer': 'no',
      // Pausing on every hiccup drifted the live behind until it fell out of
      // the provider window: drop late frames and stay on the live edge.
      'cache-pause': 'no',
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
      // Live: no reconnect_streamed. It resumed with a Range request that
      // IPTV servers reject on live channels ("Segnale interrotto" loops).
      'stream-lavf-o': isLive
          ? 'reconnect=1,reconnect_at_eof=1,reconnect_on_network_error=1,'
                'reconnect_delay_max=2'
          : 'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,'
                'reconnect_delay_max=5',
      'demuxer-lavf-o': isLive
          // Keep the broadcast PCR/PTS: genpts rewrote them (A/V drift) and
          // nobuffer starved the decoder of keyframes.
          ? 'fflags=+discardcorrupt'
          : 'fflags=+discardcorrupt+genpts',
      // Enough to find the video stream of an MPEG-TS channel without
      // making the first picture wait several seconds.
      // Broadcast MPEG-TS repeats SPS/PPS only on keyframes (every 2-5 s):
      // a 2 MB / 2 s probe often started the decoder without them.
      'demuxer-lavf-probesize': previewMode
          ? '3000000'
          : isLive
          ? '5000000'
          : '10000000',
      'demuxer-lavf-analyzeduration': previewMode
          ? '2'
          : isLive
          ? '4'
          : '5',
      'demuxer-lavf-probe-info': 'auto',
      'hls-bitrate': 'max',
      if (isLive)
        'demuxer-max-bytes':
            '${previewMode ? 8 : (DeviceTypeService.isTv ? 16 : 64)}MiB',
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
    // "mediacodec" exists only on Android: on iPhone it decoded audio with
    // a black picture. VideoToolbox is Apple's hardware decoder.
    _ => Platform.isIOS || Platform.isMacOS
        ? 'videotoolbox-copy'
        : Platform.isAndroid ? 'mediacodec-copy' : 'auto-safe',
  };

  Timer? _blackWatch;
  bool _firstFrameRendered = false;

  /// True only when decoded frames really flow through mpv's video chain.
  /// The old check used the track resolution, which mpv reads from the
  /// stream headers before the decoder outputs anything: a channel with
  /// audio and a black picture looked "fine" and the fallback never ran.
  Future<bool?> _framesFlowing() async {
    // estimated-frame-number is derived from playback time, not output.
    // Only the controller's rendering signal confirms startup succeeded.
    return _firstFrameRendered;
  }

  /// Audio playing but no decoded video frame = black screen. Checked every
  /// second for the whole playback (a decoder can also stall mid-stream);
  /// after ~5 s without frames the session reopens the channel in FFmpeg
  /// software decoding and remembers it for the next time.
  void _watchBlackScreen() {
    _blackWatch?.cancel();
    var checking = false;
    // Allow provider keyframe intervals and surface attachment to finish;
    // a two-second threshold repeatedly interrupts otherwise valid live.
    final limit = softwareDecode ? 15 : 10;
    final health = VideoHealth(missingLimit: limit);
    _blackWatch = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_disposed) return _blackWatch?.cancel();
      if (checking) return;
      final st = _player.state;
      final hasVideoTrack = st.tracks.video.any(
        (t) => t.id != 'auto' && t.id != 'no',
      );
      // Radio / audio-only channels and paused or buffering players.
      if (!hasVideoTrack || !st.playing || st.buffering) {
        health.check(playing: st.playing, buffering: st.buffering,
            audioOnly: !hasVideoTrack, frameAvailable: null);
        return;
      }
      checking = true;
      final flowing = await _framesFlowing();
      checking = false;
      if (_disposed) return;
      if (health.check(playing: st.playing, buffering: st.buffering,
          audioOnly: !hasVideoTrack, frameAvailable: flowing)) {
        _blackWatch?.cancel();
        _onError('Nessuna immagine dal flusso (schermo nero)');
      }
    });
  }

  @override
  Future<void> open({double initialVolume = 1}) async {
    // VideoController applies native output/hwdec options after a frame.
    // Tune only after that initialization, so it cannot overwrite tuning.
    await _videoController.platform.future;
    if (_disposed) throw const PlaybackException('Chiuso');
    await _tuneNetwork(effectiveStreamUserAgent(_settings.userAgent));
    // Live tuning (no frame drops, codec allowlist, deinterlacing) matters
    // on phones too: iPhone showed the same audio-with-black-picture bug.
    if (DeviceTypeService.isTv || isLive) await _tuneForTv();
    if (isLive && !previewMode) await _enableTimeshift();
    if (_disposed) throw const PlaybackException('Chiuso');
    await _player.setVolume(initialVolume.clamp(0.0, 1.0) * 100);
    _playing = Completer<void>();
    try {
      final ua = effectiveStreamUserAgent(_settings.userAgent);
      await _player.open(
        Media(_urlWithUserAgent(ua), httpHeaders: {'User-Agent': ua}),
        play: true,
      );
    } catch (e) {
      throw PlaybackException('$e');
    }
    if (_disposed) throw const PlaybackException('Chiuso');
    await _player.setRate(isLive ? 1.0 : _settings.defaultSpeed);
    unawaited(_observeFirstFrame());
    _watchBlackScreen();
    await _playing!.future.timeout(
      Duration(seconds: _settings.startTimeoutSeconds + 5),
      onTimeout: () =>
          throw const PlaybackException('Il flusso non risponde (timeout)'),
    );
  }

  String _urlWithUserAgent(String ua) => url; // media_kit uses httpHeaders.

  Future<void> _observeFirstFrame() async {
    try {
      await _videoController.waitUntilFirstFrameRendered;
      if (!_disposed) _firstFrameRendered = true;
    } catch (_) {
      // The existing session deadline/recovery handles controller failure.
    }
  }

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
    if (_playing != null && !_playing!.isCompleted) {
      _playing!.completeError(const PlaybackException('Chiuso'));
      _playing!.future.catchError((_) {});
    }
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _player.dispose();
    } catch (_) {}
    super.dispose();
  }
}
