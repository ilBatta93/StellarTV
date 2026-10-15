import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stellar_tv/models/player_settings.dart';
import 'package:stellar_tv/player/playback_engine.dart';
import 'package:stellar_tv/providers/app_provider.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/screens/multiview_screen.dart';
import 'package:stellar_tv/theme/app_theme.dart';
import 'october_live_multiview_test.dart' as fixtures;

class FakeEngine extends PlaybackEngine {
  FakeEngine(this.id, this.engines);
  final int id;
  final List<FakeEngine> engines;
  double volume = 0;
  double? openedVolume;
  bool disposed = false;
  @override
  PlayerEngineType get type => PlayerEngineType.mediakit;
  @override
  PlaybackSnapshot get value => const PlaybackSnapshot(
    isReady: true,
    isPlaying: true,
    size: Size(1920, 1080),
  );
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
    openedVolume = initialVolume;
    await setVolume(initialVolume);
  }

  @override
  Widget buildView(double ratio) => ColoredBox(
    color: id.isEven ? AppColors.card : AppColors.surface,
    child: Center(
      child: Icon(Icons.live_tv, size: 72, color: AppColors.textMuted),
    ),
  );
  @override
  Future<void> setVolume(double v) async {
    volume = v;
    expect(
      engines.where((e) => e.volume > 0 && !e.disposed).length,
      lessThanOrEqualTo(1),
    );
  }

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seekTo(Duration p) async {}
  @override
  Future<void> setSpeed(double s) async {}
  @override
  Future<void> applyFitMode(VideoFitMode m, double r) async {}
  @override
  Future<List<MediaTrack>> getAudioTracks() async => [];
  @override
  Future<void> selectAudioTrack(MediaTrack t) async {}
  @override
  Future<List<MediaTrack>> getSubtitleTracks() async => [];
  @override
  Future<void> selectSubtitleTrack(MediaTrack? t) async {}
  @override
  Future<List<MediaTrack>> getQualityTracks() async => [];
  @override
  Future<void> selectQualityTrack(MediaTrack? t) async {}
  @override
  Future<void> setSubtitleDelay(Duration d) async {}
  @override
  Future<void> setAudioDelay(Duration d) async {}
  @override
  void dispose() {
    disposed = true;
    volume = 0;
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  fixtures.mainSetupForRemote();
  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    testWidgets(
      'MultiView remote add select layout expand remove Back ${size.width}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = fixtures.TestApp();
        final settings = UiSettings();
        await settings.load();
        final engines = <FakeEngine>[];
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AppProvider>.value(value: app),
              ChangeNotifierProvider<UiSettings>.value(value: settings),
            ],
            child: MaterialApp(
              theme: AppTheme.darkTheme(isTv: true),
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RepaintBoundary(
                        key: boundaryKey,
                        child: MultiViewScreen(
                          initialChannel: app.channels.first,
                          engineFactory: (_) {
                            final e = FakeEngine(engines.length, engines);
                            engines.add(e);
                            return e;
                          },
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Apri'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Apri'));
        await tester.pumpAndSettle();
        expect(engines.single.openedVolume, 0);
        expect(engines.single.volume, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        // The add control is reached upward from the first tile; activate with OK.
        var add = find.byTooltip('Aggiungi canale');
        final addStop = find
            .ancestor(of: add, matching: find.byType(ExcludeFocus))
            .first;
        Focus.of(tester.element(addStop)).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(engines.single.volume, 0);
        expect(find.text('Canale due'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(engines.length, 2);
        expect(engines.last.openedVolume, 0);
        expect(engines.last.volume, 1);
        expect(engines.first.volume, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(engines.first.volume, 1);
        expect(engines.last.volume, 0);
        final boundary = boundaryKey.currentContext?.findRenderObject();
        if (boundary is RenderRepaintBoundary) {
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (bytes != null)
              await File(
                '/tmp/stv/multiview-${size.width.toInt()}.png',
              ).writeAsBytes(bytes.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(MultiViewScreen), findsOneWidget);
        final layoutStop = find
            .ancestor(
              of: find.byTooltip('Disposizione'),
              matching: find.byType(ExcludeFocus),
            )
            .first;
        Focus.of(tester.element(layoutStop)).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(engines.every((e) => e.volume == 0), true);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Rimuovi canale'), findsOneWidget);
        final removeStop = find
            .ancestor(
              of: find.byTooltip('Rimuovi canale'),
              matching: find.byType(ExcludeFocus),
            )
            .first;
        Focus.of(tester.element(removeStop)).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(find.text('MultiView · 1/4'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(MultiViewScreen), findsNothing);
        await tester.pump(const Duration(milliseconds: 400));
        expect(engines.every((e) => e.volume == 0 && e.disposed), true);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        app.dispose();
        settings.dispose();
      },
    );
  }
}
