import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

import '../models/player_settings.dart';
import 'playback_engine.dart';

class VlcEngine extends PlaybackEngine {
  VlcEngine({required String url, required PlayerSettings settings})
      : _url = url,
        _settings = settings,
        _controller = _createController(url, settings, settings.hardwareDecoding) {
    _ready.future.ignore();
    _controller.addListener(_sync);
    // The native player only initializes once its platform view is mounted
    // (buildView); drive play() from there, not from open().
  }

  static VlcPlayerController _createController(String url, PlayerSettings settings, HardwareDecoding hw) {
    return VlcPlayerController.network(
      url,
      hwAcc: _hwAcc(hw),
      autoPlay: false,
      autoInitialize: true,
      allowBackgroundPlayback: settings.backgroundAudio,
      options: _options(settings),
    );
  }

  final String _url;
  final PlayerSettings _settings;
  VlcPlayerController _controller;
  Completer<void> _ready = Completer<void>();
  PlaybackSnapshot _value = const PlaybackSnapshot();
  bool _disposed = false;
  bool _started = false;
  // -12847 / "media format not supported" is typically the hardware decoder
  // refusing the stream; retry once with software decoding before giving up.
  bool _retriedSoftware = false;

  static HwAcc _hwAcc(HardwareDecoding mode) => switch (mode) {
        HardwareDecoding.auto => HwAcc.auto,
        HardwareDecoding.full => HwAcc.full,
        HardwareDecoding.decoding => HwAcc.decoding,
        HardwareDecoding.disabled => HwAcc.disabled,
      };

  static VlcPlayerOptions _options(PlayerSettings s) {
    final ua = s.userAgent.trim();
    return VlcPlayerOptions(
      advanced: VlcAdvancedOptions([
        VlcAdvancedOptions.networkCaching(s.networkCachingMs),
        VlcAdvancedOptions.liveCaching(s.liveCachingMs),
      ]),
      http: VlcHttpOptions([
        if (s.httpReconnect) VlcHttpOptions.httpReconnect(true),
        if (ua.isNotEmpty) VlcHttpOptions.httpUserAgent(ua),
      ]),
      video: VlcVideoOptions([
        VlcVideoOptions.dropLateFrames(s.dropLateFrames),
      ]),
      audio: VlcAudioOptions([
        VlcAudioOptions.audioTimeStretch(s.audioTimeStretch),
        // SPDIF passthrough makes VLC fail with unsupported-format errors on
        // many iOS streams, so it is only enabled when explicitly requested.
        if (s.audioPassthrough) '--spdif',
      ]),
    );
  }

  @override
  PlayerEngineType get type => PlayerEngineType.vlc;

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

  Future<void> _retryWithSoftwareDecoding() async {
    _retriedSoftware = true;
    final old = _controller;
    old.removeListener(_sync);
    _controller = _createController(
        _url, _settings, HardwareDecoding.disabled);
    _controller.addListener(_sync);
    _ready = Completer<void>();
    _ready.future.ignore();
    try {
      await old.stopRendererScanning();
    } catch (_) {}
    await old.dispose();
    if (!_disposed) {
      if (!_controller.value.isInitialized) {
        await _controller.initialize();
      }
      if (!_disposed) await _controller.play();
    }
  }

  void _sync() {
    if (_disposed) return;
    final v = _controller.value;
    final failed = v.playingState == PlayingState.error ||
        v.errorDescription.isNotEmpty;
    if (failed && !_retriedSoftware) {
      _value = _snapshot(v, isBuffering: true);
      notifyListeners();
      _retryWithSoftwareDecoding().catchError((Object e) {
        _fail('$e');
      });
      return;
    }
    if (failed) {
      _fail(v.errorDescription.isNotEmpty
          ? v.errorDescription
          : 'VLC non riesce ad aprire il flusso');
      return;
    }
    _value = _snapshot(v);
    if (!_ready.isCompleted &&
        (v.isPlaying || v.playingState == PlayingState.playing)) {
      _ready.complete();
    }
    notifyListeners();
  }

  /// Waits for the platform view to initialize the player, then starts
  /// playback. Called by open(); the view must be mounted for this to work.
  Future<void> _initializeAndPlay() async {
    if (_started) return;
    _started = true;
    try {
      if (!_controller.value.isInitialized) {
        await _controller.initialize();
      }
      if (!_disposed) await _controller.play();
    } catch (e) {
      _fail('$e');
    }
  }

  void _fail(String message) {
    _value = _snapshot(_controller.value, error: message);
    if (!_ready.isCompleted) {
      _ready.completeError(PlaybackException(message));
      _ready.future.ignore();
    }
    notifyListeners();
  }

  PlaybackSnapshot _snapshot(VlcPlayerValue v,
      {bool isBuffering = false, String? error}) {
    return PlaybackSnapshot(
      isReady: v.isInitialized,
      isPlaying: v.isPlaying,
      isBuffering: isBuffering || v.isBuffering,
      isEnded: v.playingState == PlayingState.ended,
      position: v.position,
      duration: v.duration,
      size: v.size,
      speed: v.playbackSpeed,
      error: error,
    );
  }

  @override
  Future<void> open() async {
    // VLC's native player needs its platform view; kick initialization off
    // now (the surface mounts immediately after) and wait for playback.
    _initializeAndPlay();
    await _ready.future;
  }

  @override
  Widget buildView(double boxRatio) {
    _initializeAndPlay();
    return VlcPlayer(
      controller: _controller,
      aspectRatio: boxRatio,
      placeholder: const SizedBox.shrink(),
    );
  }

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
      _controller.setVolume((volume.clamp(0.0, 1.0) * 100).round());

  // VLC letterboxes inside its surface, so stretched modes need an explicit
  // aspect override matching the surface.
  @override
  Future<void> applyFitMode(VideoFitMode mode, double boxRatio) async {
    final ratio = switch (mode) {
      VideoFitMode.fit || VideoFitMode.zoom => _value.aspectRatio,
      VideoFitMode.fill => boxRatio,
      VideoFitMode.ratio16x9 => 16 / 9,
      VideoFitMode.ratio4x3 => 4 / 3,
      VideoFitMode.ratio21x9 => 21 / 9,
    };
    await _controller.setVideoAspectRatio(_ratioLabel(ratio));
  }

  static String _ratioLabel(double ratio) {
    // VLC rejects ratios with more than 3 decimals; round to a clean x:1000.
    final n = (ratio * 1000).round();
    final gcd = _gcd(n, 1000);
    return '${n ~/ gcd}:${1000 ~/ gcd}';
  }

  static int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

  Future<List<MediaTrack>> _tracks(
    Future<Map<int, String>> Function() list,
    Future<int?> Function() current,
  ) async {
    final tracks = await list();
    final active = await current();
    return [
      for (final e in tracks.entries)
        if (e.key >= 0)
          MediaTrack(
            id: e.key.toString(),
            label: e.value.isEmpty ? 'Traccia ${e.key}' : e.value,
            selected: e.key == active,
          ),
    ];
  }

  @override
  Future<List<MediaTrack>> getAudioTracks() =>
      _tracks(_controller.getAudioTracks, _controller.getAudioTrack);

  @override
  Future<void> selectAudioTrack(MediaTrack track) =>
      _controller.setAudioTrack(int.parse(track.id));

  @override
  Future<List<MediaTrack>> getSubtitleTracks() =>
      _tracks(_controller.getSpuTracks, _controller.getSpuTrack);

  @override
  Future<void> selectSubtitleTrack(MediaTrack? track) =>
      _controller.setSpuTrack(track == null ? -1 : int.parse(track.id));

  @override
  Future<List<MediaTrack>> getQualityTracks() async => const [];

  @override
  Future<void> selectQualityTrack(MediaTrack? track) async {}

  @override
  Future<void> setSubtitleDelay(Duration delay) =>
      _controller.setSpuDelay(delay.inMilliseconds);

  @override
  Future<void> setAudioDelay(Duration delay) =>
      _controller.setAudioDelay(delay.inMilliseconds);

  @override
  Future<void> dispose() async {
    _disposed = true;
    _controller.removeListener(_sync);
    if (!_ready.isCompleted) {
      _ready.completeError(const PlaybackException('Riproduzione annullata'));
      _ready.future.ignore();
    }
    try {
      await _controller.stopRendererScanning();
    } catch (_) {}
    await _controller.dispose();
    super.dispose();
  }
}
