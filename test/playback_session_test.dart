import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stellar_tv/models/player_settings.dart';
import 'package:stellar_tv/player/decoder_memory.dart';
import 'package:stellar_tv/player/playback_engine.dart';
import 'package:stellar_tv/player/playback_session.dart';

/// Fake native player: counts how many are alive at the same time.
class _FakeEngine extends PlaybackEngine {
  _FakeEngine(this.type, this.url, {required this.succeed});

  static int alive = 0;
  static int maxAlive = 0;

  @override
  final PlayerEngineType type;
  final String url;
  final bool succeed;
  bool disposed = false;
  Completer<void>? releaseGate;
  Duration? sought;
  bool defaultLiveSought = false;
  @override
  bool get supportsTimeshift => _value.nativeLiveSeekable;
  void liveWindow() {
    _value = const PlaybackSnapshot(
      isReady: true,
      isPlaying: true,
      nativeLiveSeekable: true,
      nativeLiveOffset: Duration(seconds: 20),
      duration: Duration(minutes: 2),
      position: Duration(seconds: 100),
    );
  }

  PlaybackSnapshot _value = const PlaybackSnapshot();

  void emitError(String message) {
    _value = PlaybackSnapshot(isReady: true, error: message);
    notifyListeners();
  }

  @override
  PlaybackSnapshot get value => _value;
  @override
  bool get supportsAudioTracks => false;
  @override
  bool get supportsSubtitleTracks => false;
  @override
  bool get supportsQualitySelection => false;
  @override
  bool get supportsDelays => false;

  @override
  Future<void> open({double initialVolume = 1}) async {
    alive++;
    if (alive > maxAlive) maxAlive = alive;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!succeed) throw const PlaybackException('HTTP 404');
    _value = const PlaybackSnapshot(isReady: true, isPlaying: true);
  }

  @override
  Widget buildView(double boxRatio) => const SizedBox();
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seekTo(Duration position) async {
    sought = position;
  }

  @override
  Future<void> seekToLive() async {
    defaultLiveSought = true;
  }

  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> applyFitMode(VideoFitMode mode, double boxRatio) async {}
  @override
  Future<List<MediaTrack>> getAudioTracks() async => const [];
  @override
  Future<void> selectAudioTrack(MediaTrack track) async {}
  @override
  Future<List<MediaTrack>> getSubtitleTracks() async => const [];
  @override
  Future<void> selectSubtitleTrack(MediaTrack? track) async {}
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
    if (disposed) return;
    disposed = true;
    await releaseGate?.future;
    alive--;
    super.dispose();
  }
}

const _xtream = 'http://tv.example.com/live/user/pass/42.m3u8';

void main() {
  test(
    'a disposal longer than four seconds never opens another decoder',
    () async {
      final gate = Completer<void>();
      final engines = <_FakeEngine>[];
      final session = PlaybackSession(
        url: _xtream,
        isLive: true,
        settings: PlayerSettings(primaryEngine: PlayerEngineType.exo),
        engineFactory: (type) {
          final engine = _FakeEngine(type, _xtream, succeed: true);
          if (engines.isEmpty) engine.releaseGate = gate;
          engines.add(engine);
          return engine;
        },
      );
      await session.start();
      final replacing = session.switchEngine(PlayerEngineType.mediakit);
      await Future<void>.delayed(const Duration(seconds: 5));
      expect(engines.length, 1);
      expect(_FakeEngine.alive, 1);
      gate.complete();
      await replacing;
      expect(engines.length, 2);
      expect(_FakeEngine.maxAlive, 1);
      session.dispose();
      await session.released;
    },
  );

  test('preview recovery remains disabled when autoFallback is off', () async {
    final types = <PlayerEngineType>[];
    final session = PlaybackSession(
      url: 'https://example.invalid/live.ts',
      isLive: true,
      previewMode: true,
      previewFallback: true,
      settings: PlayerSettings(autoFallback: false),
      engineFactory: (type) {
        types.add(type);
        return _FakeEngine(type, _xtream, succeed: false);
      },
    );
    await session.start();
    expect(types, [PlayerEngineType.exo]);
    session.dispose();
    await session.released;
  });

  test(
    'Native DVR clamps to actual window and LIVE uses native default',
    () async {
      final engine = _FakeEngine(PlayerEngineType.exo, _xtream, succeed: true);
      final session = PlaybackSession(
        url: _xtream,
        isLive: true,
        settings: PlayerSettings(primaryEngine: PlayerEngineType.exo),
        engineFactory: (_) => engine,
      );
      await session.start();
      engine.liveWindow();
      expect(session.liveDelay, const Duration(seconds: 20));
      await session.timeshiftBy(const Duration(minutes: -5));
      expect(engine.sought, Duration.zero);
      await session.timeshiftBy(const Duration(minutes: 5));
      expect(engine.sought, const Duration(minutes: 2));
      await session.goLive();
      expect(engine.defaultLiveSought, isTrue);
      session.dispose();
      await session.released;
    },
  );

  test(
    'Black-video software decoding works even with engine fallback off',
    () async {
      late PlaybackSession session;
      final types = <PlayerEngineType>[];
      _FakeEngine? current;
      session = PlaybackSession(
        url: _xtream,
        isLive: true,
        settings: PlayerSettings(
          primaryEngine: PlayerEngineType.exo,
          autoFallback: false,
        ),
        engineFactory: (type) {
          types.add(type);
          final engine = _FakeEngine(type, session.currentUrl, succeed: true);
          current = engine;
          return engine;
        },
      );
      await session.start();
      current?.emitError('schermo nero');
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(types, [PlayerEngineType.exo, PlayerEngineType.mediakit]);
      session.dispose();
      await session.released;
    },
  );

  setUp(() async {
    await DecoderMemory.clear();
    _FakeEngine.alive = 0;
    _FakeEngine.maxAlive = 0;
  });

  test('tries every address with the same engine before switching, '
      'never two players at once', () async {
    final opened = <String>[];
    late PlaybackSession session;
    session = PlaybackSession(
      url: _xtream,
      isLive: true,
      settings: PlayerSettings(primaryEngine: PlayerEngineType.exo),
      engineFactory: (type) {
        final url = session.currentUrl;
        opened.add('${type.name} $url');
        // Only mpv on the MPEG-TS address works.
        return _FakeEngine(
          type,
          url,
          succeed: type == PlayerEngineType.mediakit && url.endsWith('.ts'),
        );
      },
    );
    await (() async {
      session.start();
      await Future<void>.delayed(const Duration(seconds: 8));
    })();
    expect(opened, [
      'exo http://tv.example.com/live/user/pass/42.ts',
      'exo http://tv.example.com/live/user/pass/42.m3u8',
      'mediakit http://tv.example.com/live/user/pass/42.ts',
    ]);
    expect(session.status, SessionStatus.playing);
    expect(_FakeEngine.maxAlive, 1);
    session.dispose();
    await session.released;
    expect(_FakeEngine.alive, 0);
  });

  test('preview on Android always uses ExoPlayer without engine '
      'fallback', () async {
    final types = <PlayerEngineType>[];
    late PlaybackSession session;
    session = PlaybackSession(
      url: _xtream,
      isLive: true,
      previewMode: true,
      settings: PlayerSettings(primaryEngine: PlayerEngineType.mediakit),
      engineFactory: (type) {
        types.add(type);
        return _FakeEngine(type, session.currentUrl, succeed: false);
      },
    );
    await (() async {
      await session.start();
    })();
    expect(types, everyElement(PlayerEngineType.exo));
    expect(session.status, SessionStatus.failed);
    expect(_FakeEngine.maxAlive, 1);
    session.dispose();
    await session.released;
    expect(_FakeEngine.alive, 0);
  });

  test('MultiView tile moves to mpv on the same address right after '
      'ExoPlayer fails', () async {
    final opened = <String>[];
    late PlaybackSession session;
    session = PlaybackSession(
      url: _xtream,
      isLive: true,
      previewMode: true,
      previewFallback: true,
      settings: PlayerSettings(primaryEngine: PlayerEngineType.exo),
      engineFactory: (type) {
        opened.add('${type.name} ${session.currentUrl}');
        return _FakeEngine(
          type,
          session.currentUrl,
          succeed: type == PlayerEngineType.mediakit,
        );
      },
    );
    await (() async {
      session.start();
      await Future<void>.delayed(const Duration(seconds: 4));
    })();
    expect(opened.take(2).toList(), [
      'exo http://tv.example.com/live/user/pass/42.ts',
      'mediakit http://tv.example.com/live/user/pass/42.ts',
    ]);
    expect(session.status, SessionStatus.playing);
    expect(_FakeEngine.maxAlive, 1);
    session.dispose();
    await session.released;
  });

  test(
    'repeated errors of the same player trigger one recovery only',
    () async {
      final engines = <_FakeEngine>[];
      late PlaybackSession session;
      session = PlaybackSession(
        url: 'http://example.com/stream.m3u8',
        isLive: true,
        settings: PlayerSettings(primaryEngine: PlayerEngineType.exo),
        engineFactory: (type) {
          final e = _FakeEngine(type, session.currentUrl, succeed: true);
          engines.add(e);
          return e;
        },
      );
      await (() async {
        await session.start();
        final first = engines.single;
        for (var i = 0; i < 5; i++) {
          first.emitError('decoder failure');
        }
        await Future<void>.delayed(const Duration(seconds: 3));
      })();
      // One reconnect, not five parallel ones.
      expect(engines.length, 2);
      expect(_FakeEngine.maxAlive, 1);
      expect(session.status, SessionStatus.playing);
      session.dispose();
      await session.released;
    },
  );

  test('formato flusso dirette sceglie il primo indirizzo provato', () {
    const url = 'http://srv.example:8080/live/u/p/42.ts';
    expect(
      PlaybackSession.liveCandidates(
        url,
        true,
        format: LiveStreamFormat.m3u8,
      ).first,
      'http://srv.example:8080/live/u/p/42.m3u8',
    );
    expect(
      PlaybackSession.liveCandidates(
        'http://srv.example:8080/u/p/42',
        true,
        format: LiveStreamFormat.ts,
      ).first,
      'http://srv.example:8080/live/u/p/42.ts',
    );
    expect(PlaybackSession.liveCandidates(url, true).first, url);
  });

  test('il formato flusso viene salvato e ricaricato', () {
    final s = PlayerSettings()..liveStreamFormat = LiveStreamFormat.m3u8;
    expect(
      PlayerSettings.fromJson(s.toJson()).liveStreamFormat,
      LiveStreamFormat.m3u8,
    );
  });

  test('dirette automatiche partono in MPEG-TS anche se salvate in HLS', () {
    expect(PlaybackSession.liveCandidates(_xtream, true), [
      'http://tv.example.com/live/user/pass/42.ts',
      'http://tv.example.com/live/user/pass/42.m3u8',
    ]);
  });

  test('canale pronto ma senza immagine passa al formato successivo', () async {
    final opened = <String>[];
    late PlaybackSession session;
    session = PlaybackSession(
      url: _xtream,
      isLive: true,
      settings: PlayerSettings(
        primaryEngine: PlayerEngineType.exo,
        autoFallback: false,
      ),
      engineFactory: (type) {
        final url = session.currentUrl;
        opened.add(url);
        return url.endsWith('.ts')
            ? _NoPictureEngine(type, url)
            : _FakeEngine(type, url, succeed: true);
      },
    );
    session.start();
    await Future<void>.delayed(const Duration(seconds: 12));
    expect(opened, [
      'http://tv.example.com/live/user/pass/42.ts',
      'http://tv.example.com/live/user/pass/42.m3u8',
    ]);
    expect(session.status, SessionStatus.playing);
    expect(_FakeEngine.maxAlive, 1);
    session.dispose();
    await session.released;
  });

  test('immagine assente: suono che avanza = decoder, fermo = server', () {
    expect(
      PlaybackSession.noPictureReason(mediaAdvancing: true),
      contains('schermo nero'),
    );
    expect(
      PlaybackSession.noPictureReason(mediaAdvancing: false),
      isNot(contains('schermo nero')),
    );
    expect(
      PlaybackSession.firstPictureDeadline(PlayerEngineType.exo),
      const Duration(seconds: 8),
    );
    expect(
      PlaybackSession.firstPictureDeadline(PlayerEngineType.mediakit),
      const Duration(seconds: 14),
    );
  });
}

/// Opens fine but stays buffering without ever drawing a picture.
class _NoPictureEngine extends _FakeEngine {
  _NoPictureEngine(PlayerEngineType type, String url)
    : super(type, url, succeed: true);

  @override
  bool? get videoFrameRendered => false;

  @override
  PlaybackSnapshot get value =>
      const PlaybackSnapshot(isReady: true, isPlaying: true, isBuffering: true);
}
