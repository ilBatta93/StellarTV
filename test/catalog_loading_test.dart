import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/catalog_load_state.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/providers/app_provider.dart';
import 'package:stellar_tv/services/catalog_cache_service.dart';
import 'package:stellar_tv/services/catalog_shelf.dart';
import 'package:stellar_tv/services/xtream_service.dart';
import 'package:stellar_tv/widgets/catalog_status_indicator.dart';

Channel channel(ContentType type) => Channel(
  id: type.name,
  name: 'Test ${type.name}',
  url: '',
  logo: '',
  group: 'Test',
  type: type,
);

class FakeXtream extends XtreamService {
  final live = Completer<List<Channel>>();
  final movies = Completer<List<Channel>>();
  final series = Completer<List<Channel>>();
  Completer<List<Channel>>? nextMovies;
  int liveCalls = 0;
  @override
  Future<List<Channel>> getLiveChannels({
    required String server,
    required String username,
    required String password,
    void Function(CatalogProgress progress)? onProgress,
  }) {
    liveCalls++;
    return live.future;
  }

  @override
  Future<List<Channel>> getVodChannels({
    required String server,
    required String username,
    required String password,
    void Function(CatalogProgress progress)? onProgress,
  }) => (nextMovies ?? movies).future;
  @override
  Future<List<Channel>> getSeriesChannels({
    required String server,
    required String username,
    required String password,
    void Function(CatalogProgress progress)? onProgress,
  }) => series.future;
}

class RecordingCache extends CatalogCacheService {
  final writes = <ContentType>[];
  @override
  Future<List<Channel>> read(String accountKey) async => const [];
  @override
  Future<List<String>> sectionPaths(String accountKey) async => const [];
  @override
  Future<bool> hasSectionFile(String accountKey) async => false;
  @override
  Future<bool> writeSection(
    String accountKey,
    ContentType type,
    List<Channel> channels, {
    bool Function()? stillAllowed,
  }) async {
    writes.add(type);
    return true;
  }
}

class PathCache extends CatalogCacheService {
  PathCache(this.paths);
  final List<String> paths;
  @override
  Future<List<Channel>> read(String accountKey) async => const [];
  @override
  Future<List<String>> sectionPaths(String accountKey) async => paths;
  @override
  Future<bool> hasSectionFile(String accountKey) async =>
      paths.any((path) => File(path).existsSync());
  @override
  Future<bool> writeSection(
    String accountKey,
    ContentType type,
    List<Channel> channels, {
    bool Function()? stillAllowed,
  }) async => true;
}

class FakeCache extends CatalogCacheService {
  final List<Channel> rows;
  FakeCache([this.rows = const []]);
  @override
  Future<List<Channel>> read(String accountKey) async => rows;
  @override
  Future<List<String>> sectionPaths(String accountKey) async => const [];
  @override
  Future<bool> hasSectionFile(String accountKey) async => false;
  @override
  Future<void> write(String accountKey, List<Channel> channels) async {}
  @override
  Future<bool> writeSection(
    String accountKey,
    ContentType type,
    List<Channel> channels, {
    bool Function()? stillAllowed,
  }) async => true;
}

Future<void> tick() => Future<void>.delayed(Duration.zero);
Future<void> sectionReady(AppProvider app, ContentType type) async {
  for (var i = 0; i < 200 && app.catalogState(type).isPending; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(app.catalogState(type).isPending, false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'kids_verdicts_v1': '{"movie:test movie":false,"tv:test series":false}',
      'tmdb_genres_v1': '{"movie:test movie":[],"tv:test series":[]}',
    }),
  );

  test(
    'cached startup completes without waiting for missing network sections',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_method': 'xtream',
        'xtream_server': 'test',
        'xtream_username': '',
        'xtream_password': '',
        'playlist_refresh_minutes': 0,
      });
      final api = FakeXtream();
      final app = AppProvider(
        xtreamService: api,
        catalogCache: FakeCache([channel(ContentType.live)]),
      );
      await app.init().timeout(const Duration(seconds: 2));
      expect(app.isInitialized, true);
      expect(app.isAuthenticated, true);
      expect(app.channelsOf(ContentType.live), hasLength(1));
      expect(api.liveCalls, 0);
      await tick();
      expect(app.isRefreshingAny, false);
      expect(app.catalogState(ContentType.movie).isPending, true);
      api.movies.complete([channel(ContentType.movie)]);
      api.series.complete([channel(ContentType.series)]);
      final seriesDeadline = DateTime.now().add(const Duration(seconds: 5));
      while (app.channelsOf(ContentType.series).isEmpty &&
          DateTime.now().isBefore(seriesDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(app.channelsOf(ContentType.series), hasLength(1));
      final refresh = app.refreshAllSections();
      await tick();
      expect(app.isRefreshingAny, true);
      api.live.complete([channel(ContentType.live)]);
      await refresh;
      app.dispose();
    },
  );

  test(
    'Sections become ready independently before global completion',
    () async {
      final api = FakeXtream();
      final app = AppProvider(xtreamService: api, catalogCache: FakeCache());
      final loading = app.loadFromXtream(
        server: 'test',
        username: '',
        password: '',
      );
      await tick();
      expect(
        app.catalogState(ContentType.live).phase,
        CatalogLoadPhase.loading,
      );
      expect(
        app.catalogState(ContentType.movie).phase,
        CatalogLoadPhase.queued,
      );
      api.live.complete([channel(ContentType.live)]);
      await sectionReady(app, ContentType.live);
      expect(app.catalogState(ContentType.live).phase, CatalogLoadPhase.ready);
      expect(app.channelsOf(ContentType.live), hasLength(1));
      expect(
        app.catalogState(ContentType.movie).phase,
        CatalogLoadPhase.loading,
      );
      expect(app.isLoading, true);
      api.movies.complete([]);
      await sectionReady(app, ContentType.movie);
      expect(app.catalogState(ContentType.movie).phase, CatalogLoadPhase.ready);
      expect(app.catalogState(ContentType.movie).hasContent, false);
      expect(
        app.catalogState(ContentType.series).phase,
        CatalogLoadPhase.loading,
      );
      api.series.complete([]);
      await loading;
      expect(app.isLoading, false);
      expect(app.catalogState(ContentType.anime).phase, CatalogLoadPhase.ready);
    },
  );

  test('a section downloaded during playback is saved only after the player closes', () async {
    final api = FakeXtream();
    final cache = RecordingCache();
    final app = AppProvider(xtreamService: api, catalogCache: cache);
    final loading = app.loadFromXtream(
      server: 'test',
      username: 'viewer',
      password: '',
    );
    await tick();
    expect(app.catalogState(ContentType.live).phase, CatalogLoadPhase.loading);
    app.setPlaybackActive(true);
    api.live.complete([channel(ContentType.live)]);
    api.movies.complete([channel(ContentType.movie)]);
    api.series.complete([channel(ContentType.series)]);
    await sectionReady(app, ContentType.live);
    expect(cache.writes, isEmpty);
    expect(app.channelsOf(ContentType.live), isEmpty);
    app.setPlaybackActive(false);
    final deadline = DateTime.now().add(const Duration(seconds: 4));
    while (cache.writes.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(cache.writes, [ContentType.live]);
    expect(app.channelsOf(ContentType.live), hasLength(1));
    await loading;
    app.dispose();
  });

  test(
    'Failure uses cache without marking unrelated sections failed',
    () async {
      final api = FakeXtream();
      final app = AppProvider(
        xtreamService: api,
        catalogCache: FakeCache([channel(ContentType.movie)]),
      );
      final loading = app.loadFromXtream(
        server: 'test',
        username: '',
        password: '',
      );
      api.live.complete([]);
      final movieLoading = DateTime.now().add(const Duration(seconds: 5));
      while (app.catalogState(ContentType.movie).phase !=
              CatalogLoadPhase.loading &&
          DateTime.now().isBefore(movieLoading)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      api.movies.completeError(Exception('offline'));
      final cached = DateTime.now().add(const Duration(seconds: 5));
      while (app.catalogState(ContentType.movie).phase ==
              CatalogLoadPhase.loading &&
          DateTime.now().isBefore(cached)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(
        app.catalogState(ContentType.movie).phase,
        CatalogLoadPhase.cached,
      );
      expect(app.catalogState(ContentType.movie).hasContent, true);
      expect(app.channelsOf(ContentType.movie), hasLength(1));
      api.series.completeError(Exception('offline'));
      await loading;
      expect(
        app.catalogState(ContentType.series).phase,
        CatalogLoadPhase.failed,
      );
      expect(app.catalogState(ContentType.live).phase, CatalogLoadPhase.ready);
      expect(app.catalogState(ContentType.series).isPending, false);
    },
  );

  test('Retrying one section leaves the others untouched', () async {
    final api = FakeXtream();
    final app = AppProvider(xtreamService: api, catalogCache: FakeCache());
    final loading = app.loadFromXtream(
      server: 'test',
      username: '',
      password: '',
    );
    api.live.complete([channel(ContentType.live)]);
    final movieLoading = DateTime.now().add(const Duration(seconds: 5));
    while (app.catalogState(ContentType.movie).phase !=
            CatalogLoadPhase.loading &&
        DateTime.now().isBefore(movieLoading)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    api.movies.completeError(Exception('offline'));
    await tick();
    api.series.complete([channel(ContentType.series)]);
    await loading;
    expect(app.catalogState(ContentType.movie).phase, CatalogLoadPhase.failed);
    final again = Completer<List<Channel>>();
    api.nextMovies = again;
    final retry = app.retrySection(ContentType.movie);
    await tick();
    expect(app.catalogState(ContentType.movie).phase, CatalogLoadPhase.loading);
    expect(app.catalogState(ContentType.live).phase, CatalogLoadPhase.ready);
    expect(app.catalogState(ContentType.series).phase, CatalogLoadPhase.ready);
    again.complete([channel(ContentType.movie)]);
    await retry;
    expect(app.catalogState(ContentType.movie).phase, CatalogLoadPhase.ready);
    expect(app.channelsOf(ContentType.live), hasLength(1));
    expect(app.channelsOf(ContentType.series), hasLength(1));
    expect(app.channelsOf(ContentType.movie), hasLength(1));
    expect(api.liveCalls, 1);
    expect(app.isLoading, false);
  });

  testWidgets('Mobile and TV indicators are fixed-size and passive', (
    tester,
  ) async {
    final api = FakeXtream();
    final app = AppProvider(xtreamService: api, catalogCache: FakeCache());
    final loading = app.loadFromXtream(
      server: 'test',
      username: '',
      password: '',
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                CatalogNavigationIcon(
                  icon: Icons.live_tv,
                  type: ContentType.live,
                ),
                CatalogStatusIndicator(type: ContentType.movie),
                CatalogStatusIndicator(type: ContentType.series),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final before = tester.getSize(find.byType(Row).first);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ExcludeFocus), findsNWidgets(3));
    expect(find.byTooltip('Diretta: Caricamento'), findsOneWidget);
    expect(find.byTooltip('Film: In attesa'), findsOneWidget);
    await tester.runAsync(() async {
      api.live.complete([]);
      api.movies.complete([]);
      api.series.complete([]);
      await loading;
    });
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byTooltip('Diretta: Pronta'), findsOneWidget);
    expect(tester.getSize(find.byType(Row).first), before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    // Allow the pre-existing kids-cache notification debounce to finish.
    await tester.pump(const Duration(milliseconds: 300));
  });

  test('kids mask publishes without opening title files', () async {
    final dir = Directory.systemTemp.createTempSync('stv_mask_');
    addTearDown(() async {
      for (var attempt = 0; attempt < 10; attempt++) {
        try {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
          return;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      }
    });
    final movie = File('${dir.path}/movie.ndjson');
    final buffer = StringBuffer()
      ..writeln(jsonEncode({'stellar_catalog': 3}));
    final rows = [
      Channel(
        id: 'kids',
        name: 'Topolino',
        url: 'https://local/kids',
        logo: '',
        group: 'Cartoni',
        type: ContentType.movie,
      ),
      Channel(
        id: 'drama',
        name: 'Dramma',
        url: 'https://local/drama',
        logo: '',
        group: 'Drama',
        type: ContentType.movie,
      ),
      Channel(
        id: 'adult',
        name: 'XXX',
        url: 'https://local/adult',
        logo: '',
        group: 'Varie',
        type: ContentType.movie,
      ),
    ];
    for (final row in rows) {
      buffer.writeln(jsonEncode(row.toMap()));
    }
    buffer.writeln(jsonEncode({'end': rows.length}));
    movie.writeAsStringSync(buffer.toString());
    final api = FakeXtream();
    final app = AppProvider(
      xtreamService: api,
      catalogCache: PathCache([
        '${dir.path}/live.ndjson',
        movie.path,
        '${dir.path}/series.ndjson',
      ]),
    );
    addTearDown(app.dispose);
    final loading = app.loadFromXtream(
      server: 'test',
      username: '',
      password: '',
    );
    await tick();
    api.live.complete(<Channel>[]);
    api.movies.complete(rows);
    api.series.complete(<Channel>[]);
    await sectionReady(app, ContentType.movie);
    expect(app.channelsOf(ContentType.movie), hasLength(2));
    CatalogShelf.forbidDiskReads = true;
    try {
      app.setKidsMode(true);
    } finally {
      CatalogShelf.forbidDiskReads = false;
    }
    expect(app.kidsMode, isTrue);
    expect(app.channelsOf(ContentType.movie), hasLength(1));
    expect(app.channelsOf(ContentType.movie).single.name, 'Topolino');
    await loading;
  });
}
