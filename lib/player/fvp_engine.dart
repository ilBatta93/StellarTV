import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:fvp/mdk.dart' as mdk;

import '../models/player_settings.dart';
import '../services/device_type_service.dart';
import 'playback_engine.dart';

/// Third engine: libmdk (FFmpeg + hardware decoders) through `fvp`, used
/// directly so it never replaces the video_player backend of ExoPlayer.
/// Reads MPEG-TS, HLS, RTMP/RTSP and every FFmpeg codec, tuned for
/// IPTV/Xtream streams (reconnect, permissive demuxing, headers).
class FvpEngine extends PlaybackEngine {
  FvpEngine({
    required this.url,
    required PlayerSettings settings,
    this.isLive = false,
    this.previewMode = false,
  }) : _settings = settings;

  final String url;
  final bool isLive;
  final bool previewMode;
  final PlayerSettings _settings;
  final mdk.Player _player = mdk.Player();
  PlaybackSnapshot _value = const PlaybackSnapshot();
  final _subs = <StreamSubscription<dynamic>>[];
  Timer? _poll;
  bool _disposed = false;
  bool _buffering = true;

  @override
  PlayerEngineType get type => PlayerEngineType.fvp;

  @override
  PlaybackSnapshot get value => _value;

  @override
  bool get supportsAudioTracks => true;

  @override
  bool get supportsSubtitleTracks => true;

  @override
  bool get supportsQualitySelection => false;

  @override
  bool get supportsDelays => false;

  void _configure() {
    final ua = _settings.userAgent.trim().isEmpty
        ? 'StellarTV/1.0'
        : _settings.userAgent.trim();
    final p = _player;
    p.setProperty('avformat.strict', 'experimental');
    p.setProperty('avformat.safe', '0');
    p.setProperty('avformat.extension_picky', '0');
    p.setProperty('avformat.allowed_segment_extensions', 'ALL');
    p.setProperty('avformat.rtsp_transport', 'tcp');
    p.setProperty('avformat.fflags', '+discardcorrupt+genpts');
    p.setProperty('avio.reconnect', '1');
    p.setProperty('avio.reconnect_streamed', '1');
    p.setProperty('avio.reconnect_on_network_error', '1');
    p.setProperty('avio.reconnect_delay_max', '7');
    p.setProperty('avio.user_agent', ua);
    p.setProperty('avio.headers', 'User-Agent: $ua\r\n');
    p.setProperty('continue_at_end', isLive ? '1' : '0');
    if (isLive) {
      // Fast start without dropping the first key frame.
      p.setProperty('avformat.analyzeduration', '1500000');
      p.setProperty('avformat.probesize', '2000000');
    }
    final hw = _settings.hardwareDecoding != HardwareDecoding.disabled;
    p.videoDecoders = hw
        ? ['MediaCodec:copy=0', 'AMediaCodec', 'VT', 'FFmpeg']
        : ['FFmpeg'];
    final liveMs = DeviceTypeService.isFireTv ? 2500 : 1500;
    p.setBufferRange(
      min: previewMode ? 300 : (isLive ? liveMs ~/ 3 : 1000),
      max: isLive ? liveMs * 4 : 20000,
      drop: false,
    );
  }

  void _sync() {
    if (_disposed) return;
    final info = _player.mediaInfo;
    final video = info.video;
    var size = _value.size;
    if (video != null && video.isNotEmpty) {
      final c = video.first.codec;
      if (c.width > 0 && c.height > 0) {
        size = Size(c.width.toDouble(), c.height.toDouble());
      }
    }
    final state = _player.state;
    final status = _player.mediaStatus;
    _value = PlaybackSnapshot(
      isReady: true,
      isPlaying: state == mdk.PlaybackState.playing,
      isBuffering: _buffering,
      isEnded: !isLive && status.test(mdk.MediaStatus.end),
      position: Duration(milliseconds: _player.position),
      duration: Duration(milliseconds: isLive ? 0 : info.duration),
      bufferedUntil: Duration(
        milliseconds: _player.position + _player.buffered(),
      ),
      size: size,
      speed: _player.playbackRate,
      error: _value.error,
    );
    notifyListeners();
  }

  @override
  Future<void> open({double initialVolume = 1}) async {
    _configure();
    _player.volume = initialVolume.clamp(0.0, 1.0);
    final ready = Completer<void>();
    _subs.add(
      _player.onMediaStatus.listen((s) {
        final n = s.newValue;
        _buffering =
            n.test(mdk.MediaStatus.buffering) ||
            n.test(mdk.MediaStatus.loading);
        if (n.test(mdk.MediaStatus.invalid) && !ready.isCompleted) {
          ready.completeError(
            const PlaybackException('Flusso non valido o non supportato'),
          );
        }
        _sync();
      }),
    );
    _subs.add(_player.onStateChanged.listen((_) => _sync()));
    _subs.add(
      _player.onEvent.listen((e) {
        if (e.category == 'reader.buffering') {
          _buffering = e.error < 100;
          _sync();
        }
        if (e.error < 0 &&
            (e.category == 'decoder.video' || e.category == 'reader.open')) {
          _fail('${e.category}: ${e.detail}');
          if (!ready.isCompleted) {
            ready.completeError(PlaybackException(e.detail));
          }
        }
      }),
    );
    _player.media = url;
    final ret = await _player.prepare();
    if (ret < 0) throw const PlaybackException('Impossibile aprire il flusso');
    // Texture is created once the first video frame size is known.
    unawaited(_player.updateTexture());
    _player.state = mdk.PlaybackState.playing;
    if (!isLive && _settings.defaultSpeed != 1.0) {
      _player.playbackRate = _settings.defaultSpeed;
    }
    _poll = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _sync();
      if (!ready.isCompleted &&
          (_player.position > 0 ||
              _player.state == mdk.PlaybackState.playing)) {
        ready.complete();
      }
    });
    await ready.future.timeout(
      Duration(seconds: _settings.startTimeoutSeconds + 5),
      onTimeout: () =>
          throw const PlaybackException('Il flusso non risponde (timeout)'),
    );
  }

  void _fail(String message) {
    if (_disposed) return;
    _value = PlaybackSnapshot(
      isReady: _value.isReady,
      position: _value.position,
      duration: _value.duration,
      size: _value.size,
      error: message,
    );
    notifyListeners();
  }

  @override
  Widget buildView(double boxRatio) => ValueListenableBuilder<int?>(
    valueListenable: _player.textureId,
    builder: (_, id, _) {
      if (id == null) return const SizedBox.expand();
      final ratio = _value.hasVideoSize ? _value.aspectRatio : 16 / 9;
      return Center(
        child: AspectRatio(
          aspectRatio: ratio,
          child: Texture(textureId: id),
        ),
      );
    },
  );

  @override
  Future<void> play() async => _player.state = mdk.PlaybackState.playing;

  @override
  Future<void> pause() async => _player.state = mdk.PlaybackState.paused;

  @override
  Future<void> seekTo(Duration position) async {
    if (isLive) return;
    await _player.seek(position: position.inMilliseconds);
  }

  @override
  Future<void> setSpeed(double speed) async => _player.playbackRate = speed;

  @override
  Future<void> setVolume(double volume) async =>
      _player.volume = volume.clamp(0.0, 1.0);

  @override
  Future<void> applyFitMode(VideoFitMode mode, double boxRatio) async {}

  String _label(Map<String, String> meta, String fallback) {
    final title = meta['title'];
    if (title != null && title.isNotEmpty) return title;
    final lang = meta['language'];
    if (lang != null && lang.isNotEmpty) return languageName(lang);
    return fallback;
  }

  @override
  Future<List<MediaTrack>> getAudioTracks() async {
    final tracks = _player.mediaInfo.audio ?? const [];
    final active = _player.activeAudioTracks;
    return [
      for (final (i, t) in tracks.indexed)
        MediaTrack(
          id: '$i',
          label: _label(t.metadata, 'Traccia audio ${i + 1}'),
          language: t.metadata['language'],
          detail: describeAudio(
            codec: t.codec.codec,
            channels: t.codec.channels,
            bitrate: t.codec.bitRate,
          ),
          selected: active.contains(i),
        ),
    ];
  }

  @override
  Future<void> selectAudioTrack(MediaTrack track) async =>
      _player.activeAudioTracks = [int.parse(track.id)];

  @override
  Future<List<MediaTrack>> getSubtitleTracks() async {
    final tracks = _player.mediaInfo.subtitle ?? const [];
    final active = _player.activeSubtitleTracks;
    return [
      for (final (i, t) in tracks.indexed)
        MediaTrack(
          id: '$i',
          label: _label(t.metadata, 'Sottotitolo ${i + 1}'),
          language: t.metadata['language'],
          selected: active.contains(i),
        ),
    ];
  }

  @override
  Future<void> selectSubtitleTrack(MediaTrack? track) async =>
      _player.activeSubtitleTracks = track == null ? [] : [int.parse(track.id)];

  @override
  Future<List<MediaTrack>> getQualityTracks() async => const [];

  @override
  Future<void> selectQualityTrack(MediaTrack? track) async {}

  @override
  Future<void> setSubtitleDelay(Duration delay) async {}

  @override
  Future<void> setAudioDelay(Duration delay) async {}

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _poll?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    _player.state = mdk.PlaybackState.stopped;
    _player.dispose();
    super.dispose();
  }
}
