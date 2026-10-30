import 'package:stellar_tv/widgets/poster_card.dart';

import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/history_entry.dart';
import 'package:stellar_tv/models/series_details.dart';
import 'package:stellar_tv/models/tmdb_item.dart';
import 'package:stellar_tv/models/tmdb_person.dart';
import 'package:stellar_tv/providers/app_provider.dart';
import 'package:stellar_tv/providers/discover_provider.dart';
import 'package:stellar_tv/providers/history_provider.dart';
import 'package:stellar_tv/providers/profile_provider.dart';
import 'package:stellar_tv/providers/reactions_provider.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/screens/home_screen.dart';
import 'package:stellar_tv/screens/title_detail_screen.dart';
import 'package:stellar_tv/models/title_trailer.dart';
import 'package:stellar_tv/models/streaming_platform.dart';
import 'package:stellar_tv/widgets/tv_focusable.dart';
import 'package:stellar_tv/widgets/episode_card.dart';
import 'package:stellar_tv/screens/series_detail_screen.dart';
import 'package:stellar_tv/services/profile_service.dart';
import 'package:stellar_tv/services/sync_service.dart';
import 'package:stellar_tv/services/tmdb_service.dart';
import 'package:stellar_tv/theme/app_theme.dart';
import 'package:stellar_tv/widgets/home_art.dart';

import 'home_banner_remote_test.dart' as fixture;
import 'october_live_multiview_test.dart' as remote;

const mediaDir = '/tmp/stellar-tv/media';
const logoUrl = 'https://preview.invalid/silo.png';
List<TmdbItem> loadTitles() => [
  for (final id in [125988, 95396, 97546, 111110])
    ?TmdbItem.tryParse(
      jsonDecode(File('$mediaDir/$id.json').readAsStringSync())
          as Map<String, dynamic>,
      fallbackType: 'tv',
    ),
];

class ArtService extends TmdbService {
  ArtService(this.titles);
  final List<TmdbItem> titles;
  @override
  Future<String?> titleLogo(TmdbItem item) async => item.id == 125988
      ? logoUrl
      : item.id == 157336
      ? 'https://preview.invalid/interstellar.png'
      : null;
  @override
  Future<TitleTrailer?> trailer(TmdbItem item) async => TitleTrailer.select(
    jsonDecode(
      File('$mediaDir/videos-${item.id}-it-IT.json').readAsStringSync(),
    ) as Map<String, dynamic>,
    'it',
  );
  @override
  Future<TmdbItem?> homeArtwork(String title, {required bool isMovie}) async =>
      titles.where((i) => i.title == title).firstOrNull ?? titles.first;
  @override
  Future<TmdbItem?> findByTitle(String title, {required bool isMovie}) async =>
      titles.first;
  @override
  Future<List<TmdbItem>> recommendations(TmdbItem item) async => [];
  @override
  Future<List<TmdbPerson>> cast(TmdbItem item) async => [];
}

class PreviewDiscover extends fixture.HomeDiscover {
  PreviewDiscover(super.tmdb, this.titles);
  final List<TmdbItem> titles;
  @override
  PlatformTops platformTop(StreamingPlatform platform) =>
      platform.name == 'Netflix'
      ? PlatformTops(movies: titles, series: titles.reversed.toList())
      : const PlatformTops();
  @override
  List<TmdbItem> get topMovies => titles;
  @override
  List<TmdbItem> get topSeries => titles;
}

class PreviewHistory extends HistoryProvider {
  PreviewHistory(super.sync, this.titles);
  final List<TmdbItem> titles;
  @override
  List<HistoryEntry> get entries => [
    for (final (index, t) in titles.indexed)
      HistoryEntry(
        contentId: 'preview-${t.id}',
        type: ContentType.series,
        title: 'ITA: ${t.title} S01E0${index + 2} FHD',
        posterUrl: t.backdropUrl ?? '',
        group: 'Serie',
        url: 'https://example.invalid/${t.id}.mp4',
        position: Duration(minutes: 14 + index * 4),
        duration: const Duration(minutes: 50),
        lastWatchedAt: DateTime.utc(2026, 10, 17, 20 - index),
        seriesKey: '${t.id}',
        seriesName: t.title,
      ),
  ];
  @override
  List<HistoryEntry> get continueWatching => entries;
}

class SeriesApp extends fixture.HomeApp {
  @override
  Channel? channelById(String id) {
    if (!id.startsWith('preview-')) return super.channelById(id);
    final index = [
      125988,
      95396,
      97546,
      111110,
    ].indexOf(int.parse(id.substring(8)));
    return Channel(
      id: id,
      name: 'Serie',
      url: 'https://example.invalid/$id.mp4',
      logo: '',
      group: 'Serie',
      type: ContentType.series,
      seriesKey: id,
      seriesName: ['Silo', 'Separazione', 'Slow Horses', 'Foundation'][index],
      season: 1,
      episode: index + 2,
    );
  }

  @override
  Future<SeriesDetails> loadSeriesDetails(
    Channel series, {
    bool force = false,
  }) async => SeriesDetails(
    series: series,
    overview: '',
    seasons: [
      SeriesSeason(
        number: 1,
        name: 'Stagione 1',
        episodes: [
          for (var i = 1; i <= 6; i++)
            SeriesEpisode(
              channel: Channel(
                id: 'silo-ep-$i',
                name: 'Silo',
                url: 'https://example.invalid/silo-$i.mp4',
                logo: loadTitles().first.backdropUrl ?? '',
                group: 'Serie',
                type: ContentType.series,
              ),
              season: 1,
              number: i,
              title: [
                'Libertà',
                'La verità',
                'Le macchine',
                'Il passato',
                'La sfida',
                'La scelta',
              ][i - 1],
            ),
        ],
      ),
    ],
  );
}

Future<void> cacheImage(
  WidgetTester tester,
  String url,
  String path,
  int width,
) async {
  await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
    final image = (await codec.getNextFrame()).image;
    final provider = ResizeImage(CachedNetworkImageProvider(url), width: width);
    final key = await provider.obtainKey(ImageConfiguration.empty);
    PaintingBinding.instance.imageCache.putIfAbsent(
      key,
      () => OneFrameImageStreamCompleter(Future.value(ImageInfo(image: image))),
    );
  });
}

Future<void> save(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary = key.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      throw StateError('No screenshot boundary');
    }
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('No image bytes');
    Directory('/tmp/stv').createSync(recursive: true);
    File('/tmp/stv/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  remote.mainSetupForRemote();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => '/tmp/stellar-tv/preview-cache',
        );
  });
  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    testWidgets('Full TV preview ${size.width}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final family in [
        'Sora',
        'Manrope',
        'Roboto',
        'Roboto-Medium',
        'Roboto-Regular',
        'MaterialIcons',
      ]) {
        final loader = FontLoader(family)
          ..addFont(
            rootBundle.load(
              family == 'MaterialIcons'
                  ? 'fonts/MaterialIcons-Regular.otf'
                  : 'assets/fonts/${family.startsWith('Roboto') ? 'Manrope' : family}.ttf',
            ),
          );
        await loader.load();
      }
      final titles = loadTitles();
      final movie = TmdbItem.tryParse(
        jsonDecode(File('$mediaDir/157336.json').readAsStringSync())
            as Map<String, dynamic>,
        fallbackType: 'movie',
      );
      if (movie == null) throw StateError('Missing movie fixture');
      for (final title in [...titles, movie]) {
        for (final w in [256, size.width.toInt(), 1280]) {
          await cacheImage(
            tester,
            title.backdropUrl ?? '',
            '$mediaDir/${title.id}.jpg',
            w,
          );
          await cacheImage(
            tester,
            (title.backdropUrl ?? '').replaceFirst('/t/p/w780/', '/t/p/w1280/'),
            '$mediaDir/${title.id}.jpg',
            w,
          );
        }
      }
      await cacheImage(tester, logoUrl, '$mediaDir/logo.png', 640);
      await cacheImage(
        tester,
        'https://preview.invalid/interstellar.png',
        '$mediaDir/logo-157336.png',
        640,
      );
      final client = SupabaseClient('https://example.invalid', 'test');
      final sync = SyncService(client);
      final app = SeriesApp(),
          discover = PreviewDiscover(ArtService(titles), titles),
          history = PreviewHistory(sync, titles),
          profile = fixture.HomeProfile(ProfileService(client), sync),
          reactions = ReactionsProvider(),
          settings = UiSettings();
      final boundaryKey = GlobalKey();
      Widget mount(Widget screen) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: app),
          ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
          ChangeNotifierProvider<HistoryProvider>.value(value: history),
          ChangeNotifierProvider<ProfileProvider>.value(value: profile),
          ChangeNotifierProvider<ReactionsProvider>.value(value: reactions),
          ChangeNotifierProvider<UiSettings>.value(value: settings),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(isTv: true),
          home: RepaintBoundary(key: boundaryKey, child: screen),
        ),
      );
      await tester.pumpWidget(mount(const HomeScreen()));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      final title = tester.getRect(find.byType(HomeTitleArt).first);
      expect(title.top, greaterThanOrEqualTo(72));
      // Press Down from selected Home menu to the real first row.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await save(tester, boundaryKey, 'home-reale-${size.width.toInt()}');
      expect(find.text('S1 · E2'), findsOneWidget);
      final first = find.byType(HomeLandscapeCard).first;
      final cardRect = tester.getRect(first);
      expect(cardRect.bottom, lessThanOrEqualTo(size.height));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await save(
        tester,
        boundaryKey,
        'home-carosello-successivo-${size.width.toInt()}',
      );
      expect(tester.takeException(), isNull);
      final heading = tester.getRect(find.text('Top 10 della settimana'));
      expect(heading.top, greaterThan(size.height - 330));
      final ranked = find.byType(RankedPosterCard).first;
      expect(tester.getRect(ranked).bottom, lessThanOrEqualTo(size.height));
      final previous = find.text('Serie viste di recente', skipOffstage: false);
      expect(tester.getRect(previous).bottom, lessThan(heading.top - 200));
      final selector = FocusManager.instance.primaryFocus;
      expect(selector, isA<TvHomeSelectorNode>());
      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
      }

      await press(LogicalKeyboardKey.arrowRight);
      expect(FocusManager.instance.primaryFocus, isA<TvHomeSelectorNode>());
      await press(LogicalKeyboardKey.arrowLeft);
      expect(FocusManager.instance.primaryFocus, same(selector));
      await press(LogicalKeyboardKey.arrowDown);
      final firstTop = FocusManager.instance.primaryFocus;
      expect(firstTop, isNot(isA<TvHomeSelectorNode>()));
      await press(LogicalKeyboardKey.arrowRight);
      expect(FocusManager.instance.primaryFocus, isNot(same(firstTop)));
      await press(LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus, same(selector));
      await press(LogicalKeyboardKey.arrowDown);
      expect(FocusManager.instance.primaryFocus, same(firstTop));
      await press(LogicalKeyboardKey.arrowUp);
      await press(LogicalKeyboardKey.arrowUp);
      final historyFirst = FocusManager.instance.primaryFocus;
      expect(historyFirst, isNot(isA<TvHomeSelectorNode>()));
      await press(LogicalKeyboardKey.arrowDown);
      expect(FocusManager.instance.primaryFocus, same(selector));
      await press(LogicalKeyboardKey.arrowDown);
      await press(LogicalKeyboardKey.arrowDown);
      final nextSelector = FocusManager.instance.primaryFocus;
      expect(nextSelector, isA<TvHomeSelectorNode>());
      expect(nextSelector, isNot(same(selector)));
      await press(LogicalKeyboardKey.arrowRight);
      expect(FocusManager.instance.primaryFocus, isA<TvHomeSelectorNode>());
      await press(LogicalKeyboardKey.arrowLeft);
      await press(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await save(
        tester,
        boundaryKey,
        'home-top-successivo-${size.width.toInt()}',
      );
      await press(LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus, same(firstTop));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      final series = Channel(
        id: 'silo',
        name: 'ITA: Silo FHD',
        url: '',
        logo: '',
        group: 'Serie TV',
        type: ContentType.series,
        seriesKey: 'silo',
        seriesName: 'Silo',
      );
      await tester.pumpWidget(
        mount(SeriesDetailScreen(series: series, item: titles.first)),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(HomeTitleArt), findsOneWidget);
      expect(tester.takeException(), isNull);
      await save(tester, boundaryKey, 'scheda-serie-${size.width.toInt()}');
      final firstEpisode = find.byType(EpisodeCard).first;
      final episodeStops = find.descendant(
        of: firstEpisode,
        matching: find.byType(TvFocusable),
      );
      final episodeFocus = tester
          .widget<TvFocusable>(episodeStops.first)
          .focusNode;
      episodeFocus?.requestFocus();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'episode-play:silo-ep-2',
      );
      await tester.pumpAndSettle();
      await save(tester, boundaryKey, 'episodi-serie-${size.width.toInt()}');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      final movieChannel = Channel(
        id: 'interstellar',
        name: 'Interstellar',
        url: 'https://example.invalid/interstellar.mp4',
        logo: '',
        group: 'Film',
        type: ContentType.movie,
      );
      await tester.pumpWidget(
        mount(TitleDetailScreen(item: movie, channel: movieChannel)),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await save(tester, boundaryKey, 'scheda-film-${size.width.toInt()}');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 12));
      history.dispose();
      discover.dispose();
      profile.dispose();
      reactions.dispose();
      settings.dispose();
      app.dispose();
      client.auth.stopAutoRefresh();
    }, skip: !File('$mediaDir/125988.json').existsSync());
  }
}
