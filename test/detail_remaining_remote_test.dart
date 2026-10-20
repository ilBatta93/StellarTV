import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/series_details.dart';
import 'package:stellar_tv/models/tmdb_item.dart';
import 'package:stellar_tv/models/tmdb_person.dart';
import 'package:stellar_tv/models/title_trailer.dart';
import 'package:stellar_tv/providers/app_provider.dart';
import 'package:stellar_tv/providers/discover_provider.dart';
import 'package:stellar_tv/providers/history_provider.dart';
import 'package:stellar_tv/providers/reactions_provider.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/providers/sync_provider.dart';
import 'package:stellar_tv/services/sync_service.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/screens/title_detail_screen.dart';
import 'package:stellar_tv/screens/series_detail_screen.dart';
import 'package:stellar_tv/screens/settings_screen.dart';
import 'package:stellar_tv/theme/app_theme.dart';
import 'home_banner_remote_test.dart' as f;
import 'october_live_multiview_test.dart' as remote;

Channel channel(String id, ContentType type) => Channel(
  id: id, name: id, url: 'https://example.invalid/$id.mp4',
  logo: '', group: '', type: type,
);

class DetailApp extends f.HomeApp {
  @override
  Future<SeriesDetails> loadSeriesDetails(Channel series, {bool force = false}) async => SeriesDetails(
    series: series, overview: '', seasons: [SeriesSeason(number: 1, name: 'Stagione 1', episodes: [
      for (var i = 1; i <= 2; i++) SeriesEpisode(channel: channel('episode-$i', ContentType.series), season: 1, number: i, title: 'Episodio $i'),
    ])],
  );
}
class DetailTmdb extends f.FakeTmdb {
  @override
  Future<List<TmdbItem>> recommendations(TmdbItem item) async => [];
  @override
  Future<List<TmdbPerson>> cast(TmdbItem item) async => [];
  @override
  Future<TitleTrailer?> trailer(TmdbItem item) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  remote.mainSetupForRemote();
  setUp(() async {
    for (final family in ['Sora', 'Manrope', 'MaterialIcons']) {
      final loader = FontLoader(family)..addFont(rootBundle.load(
        family == 'MaterialIcons' ? 'fonts/MaterialIcons-Regular.otf' : 'assets/fonts/$family.ttf'));
      await loader.load();
    }
  });
  for (final tv in [true, false]) {
    testWidgets('Detail buttons read real history and threshold changes, TV=$tv', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('stellartv/device'), (_) async => tv);
      await DeviceTypeService.initialize();
      debugDefaultTargetPlatformOverride = null;
      tester.view.physicalSize = tv ? const Size(960, 540) : const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = SupabaseClient('https://example.invalid', 'test', authOptions: const AuthClientOptions(autoRefreshToken: false));
      final sync = SyncService(client), app = DetailApp(), settings = UiSettings();
      await settings.load();
      final history = HistoryProvider(sync);
      await history.switchProfile('viewer');
      settings.addListener(() => history.setWatchedPercent(settings.watchedPercent));
      final discover = f.HomeDiscover(DetailTmdb()), reactions = ReactionsProvider();
      final syncProvider = SyncProvider(sync);
      final boundary = GlobalKey();
      Widget mount(Widget page) => MultiProvider(providers: [
        ChangeNotifierProvider<AppProvider>.value(value: app),
        ChangeNotifierProvider<HistoryProvider>.value(value: history),
        ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
        ChangeNotifierProvider<ReactionsProvider>.value(value: reactions),
        ChangeNotifierProvider<UiSettings>.value(value: settings),
        ChangeNotifierProvider<SyncProvider>.value(value: syncProvider),
      ], child: MaterialApp(theme: AppTheme.darkTheme(isTv: tv), home: RepaintBoundary(key: boundary, child: page)));
      Future<void> capture(String name) async {
        final render = boundary.currentContext?.findRenderObject();
        if (render is RenderRepaintBoundary) await tester.runAsync(() async {
          final image = await render.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          if (data != null) { await Directory('/tmp/stv').create(recursive: true); await File('/tmp/stv/$name-$tv.png').writeAsBytes(data.buffer.asUint8List()); }
          image.dispose();
        });
      }
      final movie = channel('Film avviato', ContentType.movie);
      await history.recordStart(movie);
      await history.updatePosition(movie.id, const Duration(minutes: 90), const Duration(minutes: 120));
      await tester.pumpWidget(mount(TitleDetailScreen(channel: movie)));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await capture('detail-movie');
      await tester.pumpWidget(const SizedBox()); await tester.pump();
      final episode = channel('episode-1', ContentType.series);
      await history.recordStart(episode);
      await history.updatePosition(episode.id, const Duration(minutes: 36), const Duration(minutes: 40));
      await tester.pumpWidget(mount(SeriesDetailScreen(series: channel('Serie avviata', ContentType.series))));
      await tester.pump(const Duration(seconds: 1));
      expect(history.entryFor(episode.id)?.startedRemainingMinutes, 4);
      expect(history.isWatched(episode.id), isFalse);
      expect(tester.takeException(), isNull);
      await capture('detail-series');
      await settings.setWatchedPercent(90);
      await tester.pump(const Duration(milliseconds: 500));
      expect(history.isWatched(episode.id), isTrue);
      expect(history.entryFor(episode.id)?.position, const Duration(minutes: 36));
      expect(history.entryFor('episode-2'), isNull);
      expect(tester.takeException(), isNull);
      await capture('detail-series-next');
      if (tv) {
        await tester.pumpWidget(const SizedBox()); await tester.pump();
        await tester.pumpWidget(mount(const SettingsScreen()));
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.text('Aspetto e Home'));
        await tester.pump(const Duration(milliseconds: 500));
        final threshold = find.text('Soglia contenuto visto');
        await tester.drag(find.byKey(const ValueKey(1)), const Offset(0, -1200));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.ensureVisible(threshold); await tester.pumpAndSettle();
        await tester.tap(threshold); await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter); await tester.pumpAndSettle();
        expect(settings.watchedPercent, 91);
        final restored = UiSettings(); await restored.load();
        expect(restored.watchedPercent, 91); restored.dispose();
        expect(tester.takeException(), isNull);
        await capture('threshold-setting');
      }
      await tester.pumpWidget(const SizedBox()); await tester.pump(const Duration(seconds: 1));
      history.dispose(); discover.dispose(); reactions.dispose(); settings.dispose(); app.dispose(); syncProvider.dispose();
    });
  }
}