import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/audio_effects.dart';
import '../models/live_buffer_policy.dart';
import '../models/player_settings.dart';
import '../models/video_resolution_policy.dart';
import '../services/audio_effects_service.dart';
import '../services/device_type_service.dart';
import '../services/display_resolution_service.dart';
import '../services/dns_service.dart';
import 'playback_engine.dart';

/// mpv-backed engine (media_kit): subtitles and several audio tracks,
/// more tolerant of difficult live streams than the previous engine.
class MediaKitEngine extends PlaybackEngine {
  MediaKitEngine({
    required this.url,
    required PlayerSettings settings,
    this.isLive = false,
    this.previewMode = false,
    this.softwareDecode = false,
    this.hardwareCopy = false,
    int bufferLevel = 0,
  }) : _settings = settings,
       _bufferLevel = bufferLevel.clamp(0, AdaptiveBuffer.maxLevel),
       _player = Player(
         configuration: PlayerConfiguration(
           // The old value (network caching ms * 1 KB, ~1.5 MB) held about a
           // second of HD video: any network hiccup stuttered. 32 MB minimum.
           // Fire TV live: raise the forward buffer to the 16 MB TV floor so
           // the first picture waits less on slow providers and jitter does not
           // stall the audio/video sync.
           bufferSize: cacheBytes(
             settings,
             isLive: isLive,
             tv: DeviceTypeService.isTv,
             preview: previewMode,
           ),
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
        hwdec: softwareDecode
            ? 'no'
            : hardwareDecoder(
                mode: settings.hardwareDecoding,
                tv: DeviceTypeService.isTv,
                vod: !isLive && !previewMode,
                ios: Platform.isIOS || Platform.isMacOS,
                android: Platform.isAndroid,
                copy: hardwareCopy,
                fireTv: DeviceTypeService.isFireTv,
              ),
        vo: null,
      ),
    );
    _player.stream.error.listen(_onMpvError);
    _player.stream.completed.listen(_onCompleted);
    _player.stream.playing.listen((_) => _sync());
    _player.stream.buffering.listen((_) => _sync());
    // mpv reports position many times per second: rebuilding the player UI
    // on each tick competed with frame presentation (micro-stutter). 4 Hz is
    // plenty for the progress bar; state changes still sync immediately.
    _player.stream.position.listen((_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastPositionSyncMs < 250) return;
      _lastPositionSyncMs = now;
      _sync();
    });
    _player.stream.duration.listen((_) => _sync());
    _player.stream.track.listen((_) => _sync());
    _player.stream.width.listen((_) => _sync());
    _player.stream.height.listen((_) => _sync());
    _sync();
  }

  /// Preview stays at 8 MB. Otherwise the stored slider is the forward
  /// cache: legacy milliseconds keep today's buffer, and a value above the
  /// floor (16 MB on TV live, 32 MB elsewhere) is the byte count mpv uses.
  @visibleForTesting
  static int cacheBytes(
    PlayerSettings settings, {
    required bool isLive,
    required bool tv,
    bool preview = false,
  }) {
    if (preview) return 8 * 1024 * 1024;
    final stored = isLive ? settings.liveCachingMs : settings.networkCachingMs;
    return PlayerSettings.migrateCacheBytes(stored, live: isLive, tv: tv);
  }

  @visibleForTesting
  static String streamLavfOptions({
    required bool reconnect,
    required bool live,
  }) {
    if (!reconnect) return 'reconnect=0';
    if (live) {
      // A continuous MPEG-TS often ends the socket between bursts. Waiting
      // out reconnect_delay_max froze the picture for that whole delay.
      return 'reconnect=1,reconnect_at_eof=1,reconnect_on_network_error=1,'
          'reconnect_delay_max=0';
    }
    return 'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,'
        'reconnect_delay_max=5';
  }

  /// Live TV still decodes MPEG-2 and VC-1 in FFmpeg, so that path keeps
  /// the cheap decoder even before a black-picture retry sets
  /// [softwareDecode]. Hardware-decoded codecs ignore these options.
  @visibleForTesting
  static bool useCheapLiveDecode({
    required bool tv,
    required bool live,
    required bool softwareDecode,
  }) => softwareDecode || (tv && live);

  /// Codecs handed to MediaCodec. Live H.264 decoded in FFmpeg could not
  /// keep 1080p25 on a four-core TV stick (buffering every few seconds), so
  /// it goes to hardware too. MPEG-2 and VC-1 stay in FFmpeg; an H.264 1080i
  /// channel that draws black is caught by the black-picture retry, which
  /// sets [softwareDecode] and is remembered by DecoderMemory.
  @visibleForTesting
  static const hardwareCodecs = 'h264,hevc,vp9,av1';

  /// mpv audio output. OpenSL cannot carry a bitstream, and on TV boxes it
  /// does not report the HDMI/system output latency: Fire TV showed the
  /// picture a constant beat ahead of the sound. AudioTrack reports the real
  /// playback position; OpenSL stays as the fallback. Phones keep the output
  /// media_kit already set.
  @visibleForTesting
  static String? audioOutput({
    required bool passthrough,
    required bool tv,
    required bool android,
    bool effects = false,
  }) {
    if (!android) return null;
    if (passthrough) return 'audiotrack';
    // Android audio effects attach only to an AudioTrack session.
    return tv || effects ? 'audiotrack,opensles' : null;
  }

  /// mpv's own equalizer, for players without an Android effects session.
  /// The bundled FFmpeg has no other audio filter (no compressor), so night
  /// mode there is limited to the Dolby decoder's compression.
  @visibleForTesting
  static String equalizerFilter(List<double> gains) {
    final bands = <String>[
      for (var i = 0; i < gains.length && i < kEqBandCenters.length; i++)
        if (gains[i] != 0)
          'equalizer=f=${kEqBandCenters[i].round()}:t=o:w=1.5:'
              'g=${gains[i].toStringAsFixed(1)}',
    ];
    return bands.isEmpty ? '' : 'lavfi=[${bands.join(',')}]';
  }

  /// Downmix centre level: lifts dialogue when 5.1 becomes stereo.
  @visibleForTesting
  static String swresampleOptions(double? centerMixLevel) =>
      centerMixLevel == null
      ? ''
      : 'center_mix_level=${centerMixLevel.toStringAsFixed(2)}';

  /// Four threads on a four-core stick leave nothing for the picture.
  @visibleForTesting
  static String decoderThreads({required bool tv, required bool live}) => !tv
      ? '0'
      : live
      ? '2'
      : '4';

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
      // Live stays on the audio clock. Film and series on TV follow the
      // panel instead, so a late audio tick is not a visible hitch.
      'video-sync': videoSync(
        tv: DeviceTypeService.isTv,
        live: isLive,
        preview: previewMode,
      ),
      'cache': 'yes',
      // Fire TV stuttered with a 3 s read-ahead on live: a deeper window
      // absorbs provider jitter; previews stay short to start quickly.
      'demuxer-readahead-secs': previewMode
          ? '1'
          : isLive
          ? (DeviceTypeService.isFireTv ? '6' : '3')
          : '20',
      'vd-lavc-fast':
          (DeviceTypeService.isFireTv ||
              useCheapLiveDecode(
                tv: DeviceTypeService.isTv,
                live: isLive,
                softwareDecode: softwareDecode,
              ))
          ? 'yes'
          : 'no',
      // Software decoding of broadcast 1080i: cheap deinterlacing, skip the
      // loop filter so weak TV CPUs keep up. Live TV already decodes
      // H.264, MPEG-2 and VC-1 in FFmpeg even before a black-picture retry,
      // so that cheaper path starts immediately.
      if (softwareDecode) 'deinterlace': 'yes',
      if (useCheapLiveDecode(
        tv: DeviceTypeService.isTv,
        live: isLive,
        softwareDecode: softwareDecode,
      ))
        'vd-lavc-skiploopfilter': 'nonref',
      // A deeper audio buffer absorbs Android audio-driver hiccups, so
      // mpv no longer repeats/skips frames to chase the audio clock.
      'audio-buffer': '0.5',
      if (!softwareDecode) 'hwdec-codecs': hardwareCodecs,
      if (isLive && !softwareDecode) 'deinterlace': 'auto',
      'cache-pause-initial': 'no',
      // Film/series: let mpv queue frames ahead of the Android surface so a
      // late vsync no longer stalls the decoder (visible micro-stutter);
      // live keeps the default low-latency path.
      if (!isLive && !previewMode) 'video-latency-hacks': 'no',
      // Film/series: no extra GL vsync on top of Flutter's own frame pacing
      // (the double wait caused uneven frame delivery on TV panels).
      if (!isLive && !previewMode) 'opengl-swapinterval': '0',
      if (!isLive && !previewMode) 'cache-secs': '30',
      // Auto threads oversubscribed entry-level quad-core TV CPUs and
      // starved the render thread; phones keep automatic detection.
      'vd-lavc-threads': decoderThreads(
        tv: DeviceTypeService.isTv,
        live: isLive,
      ),
    };
    for (final entry in options.entries) {
      try {
        await platform.setProperty(entry.key, entry.value);
      } catch (_) {}
    }
  }

  /// Fire TV live: open with preview-sized probe settings so the first frame
  /// arrives quickly, then widen to the full live window after the frame is
  /// rendered. `cache-pause` stays off throughout.
  Future<void> _tuneForTvLiveShortProbe() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    // Apply all normal TV tuning first, then override only the probe depth.
    await _tuneForTv();
    final shortOptions = {
      // Preview-sized probe: 3 MB / 2 s — fast first frame.
      'demuxer-lavf-probesize': '3000000',
      'demuxer-lavf-analyzeduration': '2',
      // Short read-ahead until the first frame is rendered.
      'demuxer-readahead-secs': '1',
    };
    for (final entry in shortOptions.entries) {
      try {
        await platform.setProperty(entry.key, entry.value);
      } catch (_) {}
    }
    // Widen the window asynchronously once the first frame is confirmed.
    unawaited(_widenAfterFirstFrame(platform));
  }

  /// After the first frame has been rendered, apply the full live probe depth.
  Future<void> _widenAfterFirstFrame(NativePlayer platform) async {
    const maxWait = Duration(seconds: 10);
    final deadline = DateTime.now().add(maxWait);
    while (!_disposed && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (_disposed) return;
      if (_firstFrameRendered) break;
    }
    if (_disposed) return;
    final wideOptions = {
      'demuxer-lavf-probesize': '5000000',
      'demuxer-lavf-analyzeduration': '4',
      'demuxer-readahead-secs': '6',
    };
    for (final entry in wideOptions.entries) {
      try {
        await platform.setProperty(entry.key, entry.value);
      } catch (_) {}
    }
  }

  int _lastPositionSyncMs = 0;
  final bool isLive;
  final bool previewMode;

  /// FFmpeg decoding on the CPU: used when the TV's hardware decoder gave
  /// audio with a black picture (MPEG-2 / interlaced broadcast channels).
  final bool softwareDecode;

  /// Phone iOS film/series retry: copy each frame when zero-copy draws nothing.
  final bool hardwareCopy;

  /// iPhone film/series can reopen once with the copy decoder.
  bool get canRetryHardwareCopy =>
      hardwareCopy == false &&
      softwareDecode == false &&
      isLive == false &&
      previewMode == false &&
      DeviceTypeService.isTv == false &&
      (Platform.isIOS || Platform.isMacOS) &&
      _settings.hardwareDecoding != HardwareDecoding.disabled;
  final PlayerSettings _settings;
  String url;
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
  int? get renderedFrameCount => _outputFrames;

  @override
  bool get audioOnly {
    final tracks = _player.state.tracks;
    bool real(String id) => id != 'auto' && id != 'no';
    return tracks.audio.any((t) => real(t.id)) &&
        !tracks.video.any((t) => real(t.id));
  }

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

  /// Full-screen live on every device, unless the viewer turned it off. The
  /// controls still follow [PlaybackSnapshot.liveWindow]: nothing to rewind
  /// is offered before the cache really holds it.
  @override
  bool get supportsTimeshift => isLive && !previewMode && _settings.liveRewind;

  /// Bytes mpv keeps behind the playback point, sized on the device RAM.
  int get _rewindBytes => liveRewindBytes(
    tv: DeviceTypeService.isTv,
    totalRamBytes: DeviceTypeService.totalRamBytes,
    lowRam: DeviceTypeService.isLowRam,
  );

  int get _forwardBytes => cacheBytes(
    _settings,
    isLive: isLive,
    tv: DeviceTypeService.isTv,
    preview: previewMode,
  );

  /// Lets mpv keep already-played live data so the viewer can pause and
  /// rewind inside it.
  Future<void> _enableTimeshift() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    final options = {
      'cache': 'yes',
      // Rewind needs seeks served from the cache. MPEG-TS timestamp resets
      // once made the cache replay already-seen minutes: the cache poll
      // detects that jump and drops the old data (see _onClockJump).
      'demuxer-seekable-cache': supportsTimeshift ? 'yes' : 'no',
      // No 'force-seekable': media_kit seeks to 0 every time the Android
      // surface is (re)attached; on a forced-seekable live stream that seek
      // jumped outside the stream (black picture, stalled player).
      'demuxer-max-back-bytes': supportsTimeshift ? '$_rewindBytes' : '0',
      'demuxer-donate-buffer': 'no',
      // Level 0 stays on the live edge and plays through a hiccup; a server
      // that keeps stalling earns a refill cushion (mpvCachePauseWait).
      ..._cachePauseOptions(),
    };
    for (final entry in options.entries) {
      try {
        await platform.setProperty(entry.key, entry.value);
      } catch (_) {}
    }
  }

  int _bufferLevel;

  Map<String, String> _cachePauseOptions() {
    final wait = mpvCachePauseWait(level: _bufferLevel, live: isLive);
    return {
      'cache-pause': wait == null ? 'no' : 'yes',
      if (wait != null) 'cache-pause-wait': wait.toStringAsFixed(1),
      if (!isLive) 'cache-secs': '${mpvCacheSeconds(_bufferLevel)}',
    };
  }

  @override
  Future<void> setBufferLevel(int level) async {
    if (previewMode || level == _bufferLevel) return;
    _bufferLevel = level;
    final platform = _player.platform;
    if (_disposed || platform is! NativePlayer) return;
    for (final entry in _cachePauseOptions().entries) {
      try {
        await platform.setProperty(entry.key, entry.value);
      } catch (_) {}
    }
  }

  // ---- Cache poll: live window, clock jumps, stalls -------------------

  Timer? _cachePoll;
  bool _polling = false;
  Duration? _lastPollPosition;
  DateTime _seekQuietUntil = DateTime.fromMillisecondsSinceEpoch(0);
  LiveWindow? _window;
  bool _underrun = false;
  int _stalls = 0;

  @override
  int get stalls => _stalls;

  /// One property read per second, full-screen only.
  void _startCachePoll() {
    if (previewMode || _disposed) return;
    _cachePoll ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => _pollCache(),
    );
  }

  Future<void> _pollCache() async {
    final platform = _player.platform;
    if (_polling || _disposed || platform is! NativePlayer) return;
    _polling = true;
    try {
      final raw = await platform
          .getProperty('demuxer-cache-state')
          .timeout(const Duration(milliseconds: 400));
      if (_disposed) return;
      Object? decoded;
      try {
        decoded = raw.isEmpty ? null : jsonDecode(raw);
      } on FormatException {
        decoded = null;
      }
      final state = CacheState.parse(decoded);
      if (state == null) return;
      final p = _player.state;
      // A rising underrun after the first picture is a stall; the start
      // of a stream and a viewer pause are not.
      if (state.underrun && !_underrun && _firstFrameRendered && p.playing) {
        _stalls++;
      }
      _underrun = state.underrun;
      if (!supportsTimeshift) return;
      final previous = _lastPollPosition;
      _lastPollPosition = p.position;
      if (previous != null &&
          liveClockJumped(
            previous: previous,
            current: p.position,
            seeking: DateTime.now().isBefore(_seekQuietUntil),
          )) {
        await _onClockJump();
        return;
      }
      final window = liveWindowAt(p.position, state.ranges);
      if (window?.start != _window?.start || window?.edge != _window?.edge) {
        _window = window;
        _sync();
      }
    } catch (_) {
      // A slow read is skipped; the next tick tries again.
    } finally {
      _polling = false;
    }
  }

  /// The stream clock went backwards without a seek: the provider restarted
  /// its timestamps. The data behind the reader now belongs to another
  /// timeline, so it is dropped (back buffer to zero for a moment) and the
  /// window starts again from the new clock.
  Future<void> _onClockJump() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    _window = null;
    _lastPollPosition = null;
    _sync();
    try {
      await platform.setProperty('demuxer-max-back-bytes', '0');
      await Future<void>.delayed(const Duration(seconds: 1));
      if (_disposed) return;
      await platform.setProperty('demuxer-max-back-bytes', '$_rewindBytes');
    } catch (_) {}
  }

  /// While the viewer pauses, the forward cache grows to the rewind budget
  /// so the stream keeps downloading and the paused minutes stay
  /// watchable. Play restores the normal forward size.
  Future<void> _growForwardForPause(bool paused) async {
    final platform = _player.platform;
    if (!supportsTimeshift || platform is! NativePlayer) return;
    final bytes = paused && _rewindBytes > _forwardBytes
        ? _rewindBytes
        : _forwardBytes;
    try {
      await platform.setProperty('demuxer-max-bytes', '$bytes');
    } catch (_) {}
  }

  Timer? _errorConfirm;

  /// media_kit forwards every error-level mpv log line (decoder "vd"/"ad",
  /// "cplayer", "stream") as an error. On IPTV streams most of them are
  /// recoverable noise (a corrupt packet, a missing PPS before the first
  /// keyframe, a hardware decoder falling back to FFmpeg) and mpv keeps
  /// playing. Treating them as fatal tore down working channels within a
  /// second. Only connection/open failures are fatal at once; anything else
  /// counts only if playback did not progress in the following seconds.
  void _onMpvError(String message) {
    if (_disposed || message.isEmpty) return;
    if (isFatalMpvError(message)) {
      _onError(message);
      return;
    }
    if (_errorConfirm?.isActive == true) return;
    final before = _player.state.position;
    _errorConfirm = Timer(confirmWindow, () {
      if (_disposed) return;
      final now = _player.state;
      final progressed =
          now.position > before ||
          (now.playing && !now.buffering && _firstFrameRendered);
      // Paused by the viewer: a frozen clock is expected, not a failure
      // (this restarted paused live channels after a moment).
      if (progressed || !now.playing) return;
      _onError(message);
    });
  }

  @visibleForTesting
  static const confirmWindow = Duration(seconds: 6);

  /// mpv messages that mean the stream cannot be opened at all.
  @visibleForTesting
  static bool isFatalMpvError(String message) {
    final m = message.toLowerCase();
    const fatal = [
      'failed to open',
      'failed to recognize file format',
      'loading failed',
      'http error',
      'server returned',
      'connection refused',
      'no such file',
      'tcp:',
      'end of file before',
    ];
    return fatal.any(m.contains);
  }

  void _onError(String message) {
    if (_disposed || message.isEmpty) return;
    final starting = _playing;
    if (starting != null && !starting.isCompleted) {
      starting.future.catchError((_) {});
      starting.completeError(PlaybackException(message));
    }
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
    // The decoded picture first: on live streams the track list starts with
    // the "auto" entry, which has no dimensions.
    if ((p.width ?? 0) > 0 && (p.height ?? 0) > 0) {
      size = Size(p.width!.toDouble(), p.height!.toDouble());
    } else {
      for (final t in p.tracks.video) {
        if ((t.w ?? 0) > 0 && (t.h ?? 0) > 0) {
          size = Size(t.w!.toDouble(), t.h!.toDouble());
          break;
        }
      }
    }
    _value = PlaybackSnapshot(
      isReady: true,
      isPlaying: p.playing,
      isBuffering: p.buffering,
      isEnded: !isLive && p.completed,
      position: p.position,
      duration: p.duration,
      bufferedUntil: p.buffer,
      size: size,
      speed: p.rate,
      error: _value.hasError ? _value.error : null,
      liveWindow: _window,
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
    // mpv has no resolver hook: plain-http streams reach the server through
    // a local proxy that resolves with the app DNS. Empty = direct.
    final dnsProxy = await DnsService.instance.streamProxyUrl();
    final options = {
      'user-agent': ua,
      'http-proxy': dnsProxy ?? '',
      'network-timeout': '20',
      'tls-verify': 'no',
      // Live: no reconnect_streamed. It resumed with a Range request that
      // live servers reject ("Segnale interrotto" loops). The switch turns
      // the whole reconnect set off.
      'stream-lavf-o': streamLavfOptions(
        reconnect: _settings.httpReconnect,
        live: isLive,
      ),
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
      'hls-bitrate': '${hlsBitrateFor(_sizeCap) ?? 'max'}',
      'demuxer-max-bytes':
          '${cacheBytes(_settings, isLive: isLive, tv: DeviceTypeService.isTv, preview: previewMode)}',
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
  /// Film/series (progressive) use zero-copy "mediacodec,mediacodec-copy":
  /// the copy variant moved every decoded frame through shared TV RAM
  /// (micro-stutter, confirmed by diagnostics); mpv falls back to copy
  /// automatically when zero-copy cannot start. Live keeps copy only.
  /// Film and series on TV follow the display. Live, previews and phones
  /// stay locked to the audio clock.
  @visibleForTesting
  static String videoSync({
    required bool tv,
    required bool live,
    required bool preview,
  }) => tv && !live && !preview ? 'display-resample' : 'audio';

  /// TV strings stay on the television path. Phones use their own decoder:
  /// iOS film/series start on VideoToolbox and can fall back to the copy
  /// path; iOS live and every Android phone stay on the copy decoder.
  @visibleForTesting
  static String hardwareDecoder({
    required HardwareDecoding mode,
    required bool tv,
    required bool vod,
    required bool ios,
    required bool android,
    bool copy = false,
    bool fireTv = false,
  }) {
    if (mode == HardwareDecoding.disabled) return 'no';
    if (!tv) {
      if (ios) return (!vod || copy) ? 'videotoolbox-copy' : 'videotoolbox';
      if (android) return 'mediacodec-copy';
    }
    if (ios) return 'videotoolbox-copy';
    if (android) {
      // Live copy asks the decoder for planar frames: the Amlogic decoder of
      // the Chromecast with Google TV converts each 1080p picture in software
      // and delivered about 8 of 25 per second. Zero-copy keeps 25 and the
      // decoder deinterlaces itself. Fire TV keeps the copy it was tuned on.
      return vod || !fireTv ? 'mediacodec,mediacodec-copy' : 'mediacodec-copy';
    }
    return 'auto-safe';
  }

  /// Opt-in diagnostics: numeric mpv metrics only. Every property is read
  /// under its own guard and with its own deadline, because a build without
  /// one must not stop the others and a stalled read must never reach the
  /// player. The values are raw mpv counters: the report keeps the numbers,
  /// never the text mpv would print.
  @override
  Future<Map<String, Object?>> metrics() async {
    final platform = _player.platform;
    if (_disposed || platform is! NativePlayer) return const {};
    final out = <String, Object?>{};
    Future<void> read(String property, String key) async {
      try {
        final value = await platform
            .getProperty(property)
            .timeout(const Duration(milliseconds: 400));
        if (value is num || value.length <= 32) {
          out[key] = value;
        }
      } catch (_) {}
    }

    await Future.wait([
      read('frame-drop-count', 'frameDropCount'),
      read('decoder-frame-drop-count', 'decoderFrameDropCount'),
      read('estimated-vf-fps', 'estimatedFps'),
      read('demuxer-cache-duration', 'cacheSeconds'),
      read('avsync', 'avSyncSeconds'),
      read('cache-used', 'cacheKib'),
      read('hwdec-current', 'hwdecCurrent'),
      read('video-codec', 'videoCodec'),
    ]);
    return out;
  }

  /// The container rate comes first: mpv's estimate needs a few seconds of
  /// pictures and jitters on live streams.
  @override
  Future<double?> videoFrameRate() async {
    final platform = _player.platform;
    if (_disposed || platform is! NativePlayer) return null;
    for (final property in const ['container-fps', 'estimated-vf-fps']) {
      try {
        final value = double.tryParse(
          await platform
              .getProperty(property)
              .timeout(const Duration(milliseconds: 400)),
        );
        if (value != null && value > 0) return value;
      } catch (_) {}
    }
    return null;
  }

  @override
  Future<List<Map<String, Object?>>> chapters() async {
    final platform = _player.platform;
    if (_disposed || isLive || previewMode || platform is! NativePlayer) {
      return const [];
    }
    try {
      final deadline = Stopwatch()..start();
      Future<String> read(String property) {
        final remaining = 2200 - deadline.elapsedMilliseconds;
        if (_disposed || remaining <= 0) {
          throw TimeoutException('Chapter read deadline');
        }
        return platform
            .getProperty(property)
            .timeout(Duration(milliseconds: remaining));
      }

      return await (() async {
        final count = int.tryParse(await read('chapter-list/count')) ?? 0;
        if (count <= 0 || count > 40 || _disposed) {
          return <Map<String, Object?>>[];
        }
        final result = <Map<String, Object?>>[];
        for (var i = 0; i < count; i++) {
          if (_disposed) return <Map<String, Object?>>[];
          final title = await read('chapter-list/$i/title');
          final time = double.tryParse(await read('chapter-list/$i/time'));
          result.add({'title': title, 'time': time});
        }
        return result;
      })().timeout(const Duration(milliseconds: 2200));
    } catch (_) {
      return const [];
    }
  }

  bool _firstFrameRendered = false;
  int? _outputFrames;
  String? _outputToken;
  String? _outputProperty;

  /// Output properties that change when a new frame is drawn. Playback time
  /// and estimated-frame-number are not output, so they are not used.
  static const _outputProperties = <String>[
    'vo-passes/fresh/0/last',
    'video-frame-info/gop-timecode',
    'video-frame-info/smpte-timecode',
  ];

  /// Samples one output token. A change increments [renderedFrameCount].
  /// The session health budget owns teardown; this only reports frames.
  Future<void> _sampleOutputSignal() async {
    final platform = _player.platform;
    if (_disposed || platform is! NativePlayer) return;
    final names = _outputProperty == null
        ? _outputProperties
        : <String>[_outputProperty!];
    for (final name in names) {
      try {
        final value = await platform
            .getProperty(name)
            .timeout(const Duration(milliseconds: 400));
        if (_disposed || value.isEmpty) continue;
        _outputProperty = name;
        if (value != _outputToken) {
          _outputToken = value;
          final next = (_outputFrames ?? 0) + 1;
          _outputFrames = next;
        }
        return;
      } catch (_) {}
    }
  }

  /// Preferences the settings screen shows for this engine. Frame dropping
  /// stays off on live: a jittery clock made mpv discard every picture at
  /// start. On film, "vo" dropping is limited to software decoding, where
  /// the CPU really falls behind; hardware film on a phone keeps mpv's own
  /// default so this does not change a path that was already smooth.
  Future<void> _applyDeclaredPreferences() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    final dropLate = !isLive && softwareDecode && _settings.dropLateFrames;
    final options = <String, String>{
      if (_settings.skipFrames) 'vd-lavc-skipframe': 'nonref',
      'audio-pitch-correction': _settings.audioTimeStretch ? 'yes' : 'no',
      'audio-spdif': _settings.audioPassthrough
          ? 'ac3,eac3,dts,dts-hd,truehd'
          : 'no',
      'ao': ?audioOutput(
        passthrough: _settings.audioPassthrough,
        tv: DeviceTypeService.isTv,
        android: Platform.isAndroid,
        effects: _effectsOutput,
      ),
      if (_audioSession != null) 'audiotrack-session-id': '${_audioSession!}',
      if (dropLate || DeviceTypeService.isTv || isLive)
        'framedrop': dropLate ? 'vo' : 'no',
    };
    for (final entry in options.entries) {
      try {
        await platform.setProperty(entry.key, entry.value);
      } catch (_) {}
    }
  }

  @override
  Future<void> open({double initialVolume = 1}) async {
    // VideoController applies native output/hwdec options after a frame.
    // Tune only after that initialization, so it cannot overwrite tuning.
    await _videoController.platform.future;
    if (_disposed) throw const PlaybackException('Chiuso');
    await _tuneNetwork(effectiveStreamUserAgent(_settings.userAgent));
    // Live tuning (codec allowlist, deinterlacing) matters on phones too:
    // iPhone showed the same audio-with-black-picture bug.
    // On Fire TV live: start with preview-sized probe (3 MB / 2 s, read-ahead
    // 1 s) so the first frame arrives quickly, then widen to the full window.
    if (DeviceTypeService.isTv || isLive) {
      if (isLive && !previewMode && DeviceTypeService.isFireTv) {
        await _tuneForTvLiveShortProbe();
      } else {
        await _tuneForTv();
      }
    }
    if (isLive && !previewMode) await _enableTimeshift();
    if (!isLive && !previewMode && _bufferLevel > 0) {
      final level = _bufferLevel;
      _bufferLevel = 0;
      await setBufferLevel(level);
    }
    if (!previewMode) {
      // Before the first AudioTrack exists: mpv reads the session at init.
      if (Platform.isAndroid) {
        _audioSession = await AudioEffectsService.instance.loadSessionId();
      } else {
        await AudioEffectsService.instance.prepare();
      }
      _effectsOutput = AudioEffectsService.instance.settings.anyEnabled;
      if (_disposed) throw const PlaybackException('Chiuso');
    }
    await _applyDeclaredPreferences();
    if (!previewMode) await _applyAudioEffects();
    if (_disposed) throw const PlaybackException('Chiuso');
    await _player.setVolume(initialVolume.clamp(0.0, 1.0) * 100);
    _playing = Completer<void>();
    try {
      final ua = effectiveStreamUserAgent(_settings.userAgent);
      await _player.open(
        Media(url, httpHeaders: {'User-Agent': ua}),
        play: true,
      );
    } catch (e) {
      throw PlaybackException('$e');
    }
    if (_disposed) throw const PlaybackException('Chiuso');
    unawaited(_capVideoVariant());
    if (!previewMode && !_effectsStarted) {
      _effectsStarted = true;
      AudioEffectsService.instance.addListener(_onAudioEffectsChanged);
      unawaited(AudioEffectsService.instance.playerStarted());
    }
    await _player.setRate(isLive ? 1.0 : _settings.defaultSpeed);
    unawaited(_observeFirstFrame());
    await _playing!.future.timeout(
      Duration(seconds: _settings.startTimeoutSeconds + 5),
      onTimeout: () =>
          throw const PlaybackException('Il flusso non risponde (timeout)'),
    );
    _startCachePoll();
  }

  @override
  Future<void> sampleOutput() => _sampleOutputSignal();

  @override
  Future<bool> reopen(String url) async {
    if (_disposed) return false;
    this.url = url;
    _firstFrameRendered = false;
    _outputFrames = null;
    _outputToken = null;
    _outputProperty = null;
    // A new stream starts a new clock and an empty window.
    _window = null;
    _lastPollPosition = null;
    _underrun = false;
    await _growForwardForPause(false);
    _playing = Completer<void>();
    try {
      final ua = effectiveStreamUserAgent(_settings.userAgent);
      await _player.open(
        Media(url, httpHeaders: {'User-Agent': ua}),
        play: true,
      );
    } catch (_) {
      return false;
    }
    if (_disposed) return false;
    unawaited(_observeFirstFrame());
    unawaited(_capVideoVariant());
    return true;
  }

  VideoSizeCap? get _sizeCap =>
      DisplayResolutionService.instance.capFor(_settings.maxResolution);

  static List<VideoTrack> _sizedVariants(Tracks tracks) => [
    for (final t in tracks.video)
      if (t.id != 'auto' && t.id != 'no' && (t.w ?? 0) > 0 && (t.h ?? 0) > 0) t,
  ];

  /// mpv opens an adaptive stream on the variant picked by bitrate; once the
  /// track list shows the real sizes, the largest one inside the cap wins.
  /// Unselected HLS variants are not downloaded. A single-picture stream has
  /// nothing to choose.
  Future<void> _capVideoVariant() async {
    final cap = _sizeCap;
    final platform = _player.platform;
    if (cap == null || platform is! NativePlayer) return;
    var variants = _sizedVariants(_player.state.tracks);
    if (variants.length < 2) {
      try {
        final tracks = await _player.stream.tracks
            .firstWhere((t) => _sizedVariants(t).length > 1)
            .timeout(const Duration(seconds: 20));
        variants = _sizedVariants(tracks);
      } catch (_) {
        return;
      }
    }
    if (_disposed) return;
    final pick = pickCappedVariant([
      for (final t in variants) (t.w!, t.h!),
    ], cap);
    if (pick == null) return;
    final chosen = variants[pick];
    try {
      final current = await platform
          .getProperty('current-tracks/video/id')
          .timeout(const Duration(milliseconds: 800));
      if (_disposed || current == chosen.id) return;
      await _player.setVideoTrack(chosen);
    } catch (_) {}
  }

  Future<void> _observeFirstFrame() async {
    try {
      await _videoController.waitUntilFirstFrameRendered;
      if (!_disposed) _firstFrameRendered = true;
    } catch (_) {
      // The existing session deadline/recovery handles controller failure.
      return;
    }
    if (!liveCatchUp(
      tv: DeviceTypeService.isTv,
      live: isLive,
      preview: previewMode,
    )) {
      return;
    }
    // Once the picture is steady, late frames may be dropped so the video
    // catches up with the audio clock. Without it a Chromecast on 1080p
    // HEVC through the copy decoder drifted 4 s behind the sound.
    await Future<void>.delayed(const Duration(seconds: 5));
    final platform = _player.platform;
    if (_disposed || platform is! NativePlayer) return;
    try {
      await platform.setProperty('framedrop', 'vo');
    } catch (_) {}
  }

  /// Full-screen TV live only. Frame dropping stays off at start (a
  /// jittery clock discarded every picture) and on previews.
  @visibleForTesting
  static bool liveCatchUp({
    required bool tv,
    required bool live,
    required bool preview,
  }) => tv && live && !preview;

  @override
  Widget buildView(double boxRatio) => Video(
    controller: _videoController,
    controls: NoVideoControls,
    fit: BoxFit.contain,
  );

  @override
  Future<void> play() async {
    await _growForwardForPause(false);
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    await _growForwardForPause(true);
  }

  @override
  Future<void> seekTo(Duration position) {
    // A viewer seek moves the clock on purpose: not a timestamp reset.
    _seekQuietUntil = DateTime.now().add(const Duration(seconds: 3));
    _lastPollPosition = null;
    return _player.seek(position);
  }

  /// The newest buffered picture, when the cache window is known.
  @override
  Future<void> seekToLive() {
    final window = _window;
    if (window == null) return seekTo(value.bufferedUntil);
    return seekTo(window.clamp(window.edge));
  }

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

  int? _audioSession;
  bool _effectsOutput = false;
  bool _effectsStarted = false;
  String? _ac3DrcDefault;

  void _onAudioEffectsChanged() => unawaited(_applyAudioEffects());

  /// The mpv side of the audio effects; the Android session effects are
  /// driven by [AudioEffectsService]. Downmix and Dolby compression take
  /// effect when the decoder next starts (track, channel or seek reload).
  Future<void> _applyAudioEffects() async {
    final platform = _player.platform;
    if (_disposed || platform is! NativePlayer) return;
    final plan = AudioEffectsService.instance.plan;
    if (_audioSession != null &&
        !DeviceTypeService.isTv &&
        !_effectsOutput &&
        !_settings.audioPassthrough &&
        AudioEffectsService.instance.settings.anyEnabled) {
      // A phone started on mpv's default output: move to AudioTrack so the
      // session effects can attach.
      _effectsOutput = true;
      try {
        await platform.setProperty('ao', 'audiotrack,opensles');
        await platform.command(['ao-reload']);
      } catch (_) {}
    }
    try {
      _ac3DrcDefault ??= await platform.getProperty('ad-lavc-ac3drc');
    } catch (_) {}
    final options = <String, String>{
      'audio-swresample-o': swresampleOptions(plan.centerMixLevel),
      if (plan.compress)
        'ad-lavc-ac3drc': '1'
      else
        'ad-lavc-ac3drc': ?_ac3DrcDefault,
      // Passthrough sends a bitstream: no filter can touch it.
      if (_audioSession == null && !_settings.audioPassthrough)
        'af': equalizerFilter(plan.eqGains),
    };
    for (final entry in options.entries) {
      try {
        await platform.setProperty(entry.key, entry.value);
      } catch (_) {}
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_effectsStarted) {
      _effectsStarted = false;
      AudioEffectsService.instance.removeListener(_onAudioEffectsChanged);
      unawaited(AudioEffectsService.instance.playerStopped());
    }
    _errorConfirm?.cancel();
    _cachePoll?.cancel();
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
