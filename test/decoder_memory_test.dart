import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:stellar_tv/models/player_settings.dart';
import 'package:stellar_tv/player/decoder_memory.dart';
import 'package:stellar_tv/player/playback_engine.dart';
import 'package:stellar_tv/player/playback_session.dart';

class _BlackEngine extends PlaybackEngine {
  _BlackEngine(this.type, {required this.black});

  @override
  final PlayerEngineType type;
  final bool black;
  PlaybackSnapshot _value = const PlaybackSnapshot();

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
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (black) {
      throw const PlaybackException(
        'Nessuna immagine dal flusso (schermo nero)',
      );
    }
    _value = const PlaybackSnapshot(isReady: true, isPlaying: true);
  }

  @override
  Widget buildView(double boxRatio) => const SizedBox();
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seekTo(Duration position) async {}
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DecoderMemory.clear();
  });

  test('same channel key for .ts, .m3u8 and addresses without /live/', () {
    const a = 'http://tv.example.com/live/user/pass/42.ts';
    const b = 'http://tv.example.com/live/user/pass/42.m3u8';
    const c = 'http://tv.example.com/user/pass/42';
    expect(DecoderMemory.keyFor(a), DecoderMemory.keyFor(b));
    expect(DecoderMemory.keyFor(a), DecoderMemory.keyFor(c));
    expect(DecoderMemory.keyFor(a), isNot(contains('pass')));
    expect(
      DecoderMemory.keyFor(a),
      isNot(DecoderMemory.keyFor('http://tv.example.com/live/user/pass/43.ts')),
    );
  });

  test(
    'a black-screen channel reopens directly in mpv software mode',
    () async {
      const url = 'http://tv.example.com/live/user/pass/42.ts';
      final first = <PlayerEngineType>[];
      final session = PlaybackSession(
        url: url,
        isLive: true,
        settings: PlayerSettings(primaryEngine: PlayerEngineType.mediakit),
        engineFactory: (type) {
          first.add(type);
          // Hardware decoder black on the first try, software works.
          return _BlackEngine(type, black: first.length == 1);
        },
      );
      await session.start();
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(session.status, SessionStatus.playing);
      expect(first, [PlayerEngineType.mediakit, PlayerEngineType.mediakit]);
      expect(DecoderMemory.needsSoftware(url), isTrue);
      session.dispose();
      await session.released;

      // Next time, even the Android preview (normally ExoPlayer) goes to mpv.
      final second = <PlayerEngineType>[];
      final preview = PlaybackSession(
        url: 'http://tv.example.com/live/user/pass/42.m3u8',
        isLive: true,
        previewMode: true,
        settings: PlayerSettings(primaryEngine: PlayerEngineType.mediakit),
        engineFactory: (type) {
          second.add(type);
          return _BlackEngine(type, black: false);
        },
      );
      await preview.start();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(second.first, PlayerEngineType.mediakit);
      expect(preview.status, SessionStatus.playing);
      preview.dispose();
      await preview.released;
    },
  );
}
