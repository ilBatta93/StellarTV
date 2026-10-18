import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/player_settings.dart';
import 'package:stellar_tv/player/playback_engine.dart';
import 'package:stellar_tv/player/playback_session.dart';
import 'package:stellar_tv/services/subtitles_service.dart';
import 'package:stellar_tv/widgets/player/player_sheets.dart';
import 'package:stellar_tv/widgets/player/subtitle_overlay.dart';

import 'player_remote_seek_test.dart' show SeekEngine;
import 'october_live_multiview_test.dart' as remote;

class SubtitleEngine extends SeekEngine {
  SubtitleEngine(PlayerEngineType type)
    : super(type, 'https://example.invalid/movie.mp4', succeed: true);
  MediaTrack? selected;
  @override
  bool get supportsSubtitleTracks => true;
  @override
  Future<List<MediaTrack>> getSubtitleTracks() async => const [
    MediaTrack(id: 'it', label: 'Italiano', language: 'it'),
  ];
  @override
  Future<void> selectSubtitleTrack(MediaTrack? track) async {
    selected = track;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  remote.mainSetupForRemote();
  test('Nested and simultaneous cues remain visible after seeking', () {
    const cues = [
      SubtitleCue(Duration.zero, Duration(seconds: 100), 'Cartello'),
      SubtitleCue(Duration(seconds: 10), Duration(seconds: 11), 'Breve'),
      SubtitleCue(Duration(seconds: 20), Duration(seconds: 21), 'Dialogo'),
    ];
    expect(
      SubtitlesService.cueAt(cues, const Duration(seconds: 50), Duration.zero),
      'Cartello',
    );
    expect(
      SubtitlesService.cueAt(
        cues,
        const Duration(milliseconds: 20500),
        Duration.zero,
      ),
      'Cartello\nDialogo',
    );
    expect(
      SubtitlesService.cueAt(cues, const Duration(seconds: 100), Duration.zero),
      isNull,
    );
  });
  test('Positive delay postpones cues; negative delay advances them', () {
    const cues = [
      SubtitleCue(Duration(seconds: 10), Duration(seconds: 11), 'Ciao'),
    ];
    expect(
      SubtitlesService.cueAt(
        cues,
        const Duration(seconds: 10),
        const Duration(seconds: 1),
      ),
      isNull,
    );
    expect(
      SubtitlesService.cueAt(
        cues,
        const Duration(seconds: 11),
        const Duration(seconds: 1),
      ),
      'Ciao',
    );
    expect(
      SubtitlesService.cueAt(
        cues,
        const Duration(seconds: 9),
        const Duration(seconds: -1),
      ),
      'Ciao',
    );
  });
  test('SRT accepts BOM, CR and rejects reversed intervals', () {
    final cues = SubtitlesService.parseSrt(
      '\uFEFF1\r00:00:01,000 --> 00:00:02,000\r<b>Città</b>\r\r2\r00:00:04,000 --> 00:00:03,000\rNo',
    );
    expect(cues.length, 1);
    expect(cues.single.text, 'Città');
  });
  testWidgets('Exo external delay adjusts with remote OK and Back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = PlaybackSession(
      url: 'https://example.invalid/movie.mp4',
      isLive: false,
      settings: PlayerSettings(primaryEngine: PlayerEngineType.exo),
    );
    await session.setExternalSubtitles(true);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSyncSheet(context, session),
              child: const Text('Apri'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Apri'));
    await tester.pumpAndSettle();
    expect(find.text('Ritardo audio'), findsNothing);
    // Move from the first delay action to -50 and activate via TV remote.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(session.subtitleDelay, const Duration(milliseconds: -50));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Ritardo sottotitoli'), findsNothing);
    session.dispose();
  });
  testWidgets(
    'External source survives delayed preferences and engine replacement',
    (tester) async {
      final engines = <SubtitleEngine>[];
      final session = PlaybackSession(
        url: 'https://example.invalid/movie.mp4',
        isLive: false,
        settings: PlayerSettings(
          primaryEngine: PlayerEngineType.exo,
          subtitlesEnabled: true,
        ),
        engineFactory: (type) {
          final engine = SubtitleEngine(type);
          engines.add(engine);
          return engine;
        },
      );
      final opening = session.start();
      await tester.pump(const Duration(milliseconds: 100));
      await session.setExternalSubtitles(true);
      await tester.pump(const Duration(seconds: 2));
      await opening;
      await tester.pump(const Duration(seconds: 2));
      expect(engines.single.selected, isNull);
      final switching = session.switchEngine(PlayerEngineType.mediakit);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 4));
      await switching;
      await tester.pump(const Duration(seconds: 2));
      expect(engines.last.selected, isNull);
      expect(session.externalSubtitlesActive, isTrue);
      await session.selectSubtitleTrack(
        const MediaTrack(id: 'it', label: 'Italiano'),
      );
      expect(session.externalSubtitlesActive, isFalse);
      expect(engines.last.selected?.id, 'it');
      session.dispose();
      await tester.pump(const Duration(seconds: 2));
      await session.released;
    },
  );
  testWidgets(
    'Overlay follows paused seek notifications without whole-screen throttling',
    (tester) async {
      final engine = SeekEngine(
        PlayerEngineType.exo,
        'https://example.invalid/movie.mp4',
        succeed: true,
      );
      final session = PlaybackSession(
        url: engine.url,
        isLive: false,
        settings: PlayerSettings(),
        engineFactory: (_) => engine,
      );
      final opening = session.start();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 2));
      await opening;
      await tester.pumpWidget(
        MaterialApp(
          home: ListenableBuilder(
            listenable: session,
            builder: (_, _) => SubtitleOverlay(
              cues: const [
                SubtitleCue(
                  Duration(seconds: 60),
                  Duration(seconds: 61),
                  'Prima',
                ),
                SubtitleCue(
                  Duration(seconds: 90),
                  Duration(seconds: 91),
                  'Dopo',
                ),
              ],
              position: session.value.position,
              delay: session.subtitleDelay,
              settings: PlayerSettings(),
            ),
          ),
        ),
      );
      expect(find.text('Prima'), findsOneWidget);
      await session.seekTo(const Duration(seconds: 90));
      await tester.pump();
      expect(find.text('Prima'), findsNothing);
      expect(find.text('Dopo'), findsOneWidget);
      session.dispose();
      await tester.pump(const Duration(seconds: 2));
      await session.released;
    },
  );
}
