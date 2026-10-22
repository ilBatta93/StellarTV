import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:stellar_tv/services/introdb_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/models/player_settings.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/player/playback_engine.dart';
import 'package:stellar_tv/providers/app_provider.dart';
import 'package:stellar_tv/providers/history_provider.dart';
import 'package:stellar_tv/screens/player_screen.dart';
import 'package:stellar_tv/services/sync_service.dart';
import 'package:stellar_tv/widgets/player/tv_player_controls.dart';

import 'october_live_multiview_test.dart' as remote;

class SeekEngine extends PlaybackEngine {
  SeekEngine(this.type, this.url, {required this.succeed});

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
  int pauses = 0;
  int plays = 0;
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

  void progress(Duration position, {bool ended = false}) {
    _value = PlaybackSnapshot(
      isReady: true,
      isPlaying: !ended,
      isEnded: ended,
      position: position,
      duration: const Duration(minutes: 10),
    );
    notifyListeners();
  }

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
    _value = const PlaybackSnapshot(
      isReady: true,
      isPlaying: true,
      position: Duration(seconds: 60),
      duration: Duration(minutes: 10),
    );
  }

  @override
  Widget buildView(double boxRatio) => const SizedBox();
  @override
  Future<void> play() async {
    plays++;
    _setPlaying(true);
  }

  @override
  Future<void> pause() async {
    pauses++;
    _setPlaying(false);
  }

  void _setPlaying(bool playing) {
    _value = PlaybackSnapshot(
      isReady: true,
      isPlaying: playing,
      position: _value.position,
      duration: _value.duration,
    );
    notifyListeners();
  }

  @override
  Future<void> seekTo(Duration position) async {
    sought = position;
    _value = PlaybackSnapshot(
      isReady: true,
      isPlaying: true,
      position: position,
      duration: const Duration(minutes: 10),
    );
    notifyListeners();
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  remote.mainSetupForRemote();
  for (final autoplay in [true, false]) {
    for (final verified in [true, false]) {
      testWidgets(
        'outro obeys autoplay=$autoplay, verified=$verified and pause',
        (tester) async {
          SharedPreferences.setMockInitialValues({
            'player_settings_tv_vod_v1': jsonEncode(
              (PlayerSettings()..autoNextEpisode = autoplay).toJson(),
            ),
          });
          tester.view.physicalSize = const Size(1280, 720);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final client = SupabaseClient(
            'https://example.invalid',
            'test',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          );
          final app = remote.TestApp();
          final history = HistoryProvider(SyncService(client));
          final first = Channel(
            id: 'episode1',
            name: 'Episode 1',
            url: 'https://example.invalid/1.mp4',
            logo: '',
            group: '',
            type: ContentType.series,
            seriesKey: 'test',
            season: 1,
            episode: 1,
          );
          final second = Channel(
            id: 'episode2',
            name: 'Episode 2',
            url: 'https://example.invalid/2.mp4',
            logo: '',
            group: '',
            type: ContentType.series,
            seriesKey: 'test',
            season: 1,
            episode: 2,
          );
          final engine = SeekEngine(
            PlayerEngineType.mediakit,
            first.url,
            succeed: true,
          );
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<AppProvider>.value(value: app),
                ChangeNotifierProvider<HistoryProvider>.value(value: history),
              ],
              child: MaterialApp(
                home: PlayerScreen(
                  channel: first,
                  queue: [first, second],
                  engineFactory: (_) => engine,
                  segmentsSource: () async => verified
                      ? const EpisodeSegments(
                          outro: SkipSegment(
                            'outro',
                            Duration(seconds: 540),
                            Duration(seconds: 600),
                          ),
                        )
                      : EpisodeSegments.empty,
                ),
              ),
            ),
          );
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 150));
          });
          await tester.pump(const Duration(milliseconds: 100));
          engine.progress(const Duration(seconds: 550));
          await tester.pump();
          await engine.pause();
          await tester.pump(const Duration(seconds: 7));
          expect(
            engine.disposed,
            false,
          ); // no countdown can advance while paused
          if (!autoplay || !verified) {
            await engine.play();
            await tester.pump(const Duration(seconds: 7));
            expect(
              engine.disposed,
              false,
            ); // off or estimated credits never auto-skip
          }
          if (!autoplay) {
            engine.progress(const Duration(seconds: 600), ended: true);
            await tester.pump();
            await tester.pump(const Duration(seconds: 2));
            expect(
              engine.disposed,
              false,
            ); // natural end obeys same off preference
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
          // The session deliberately waits 350 ms before releasing its surface.
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump();
          history.dispose();
          app.dispose();
          client.dispose();
        },
      );
    }
  }
  for (final type in PlayerEngineType.values) {
    testWidgets('Remote seek stays hidden on $type, OK still opens commands', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = SupabaseClient(
        'https://example.invalid',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final app = remote.TestApp();
      final history = HistoryProvider(SyncService(client));
      final engine = SeekEngine(
        type,
        'https://example.invalid/movie.mp4',
        succeed: true,
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppProvider>.value(value: app),
            ChangeNotifierProvider<HistoryProvider>.value(value: history),
          ],
          child: MaterialApp(
            home: PlayerScreen(
              channel: Channel(
                id: 'movie',
                name: 'Film',
                url: engine.url,
                logo: '',
                group: 'Film',
                type: ContentType.movie,
              ),
              engineFactory: (_) => engine,
              segmentsSource: () async => const EpisodeSegments(
                intro: SkipSegment(
                  'intro',
                  Duration(seconds: 190),
                  Duration(seconds: 220),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump(const Duration(milliseconds: 100));

      expect(DeviceTypeService.isTv, true);
      expect(engine.value.isPlaying, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(engine.value.isPlaying, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(engine.disposed, false);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(engine.value.isPlaying, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(engine.disposed, false);
      expect(
        find.byType(TvPlayerControls, skipOffstage: false),
        findsOneWidget,
      );
      double opacity() => tester
          .widget<AnimatedOpacity>(
            find
                .ancestor(
                  of: find.byType(TvPlayerControls, skipOffstage: false),
                  matching: find.byType(AnimatedOpacity, skipOffstage: false),
                )
                .first,
          )
          .opacity;
      expect(opacity(), 0);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(opacity(), 0);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(opacity(), 0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 701));
      expect(engine.sought, const Duration(seconds: 100));
      expect(opacity(), 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 701));
      expect(engine.sought, const Duration(seconds: 90));
      expect(opacity(), 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaFastForward);
      await tester.pump(const Duration(milliseconds: 701));
      expect(engine.sought, const Duration(seconds: 120));
      expect(opacity(), 0);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacity(), 1);
      expect(engine.pauses, 1);
      expect(engine.value.isPlaying, false);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(engine.pauses, 1);
      expect(engine.plays, 0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(engine.plays, 1);
      expect(engine.value.isPlaying, true);
      // Down selects the progress row: arrows seek but do not close the panel.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 701));
      expect(engine.sought, const Duration(seconds: 130));
      expect(opacity(), 1);
      expect(tester.takeException(), isNull);
      await engine.seekTo(const Duration(seconds: 195));
      await tester.pump();
      expect(opacity(), 0);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(engine.sought, const Duration(seconds: 220));
      expect(opacity(), 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      app.dispose();
      history.dispose();
    });
  }
}
