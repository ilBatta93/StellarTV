import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/catalog_load_state.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/providers/app_provider.dart';
import 'package:stellar_tv/services/catalog_cache_service.dart';
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

class FakeCache extends CatalogCacheService {
  final List<Channel> rows;
  FakeCache([this.rows = const []]);
  @override
  Future<List<Channel>> read(String accountKey) async => rows;
  @override
  Future<void> write(String accountKey, List<Channel> channels) async {}
  @override
  Future<void> writeSection(
    String accountKey,
    ContentType type,
    List<Channel> channels,
  ) async {}
}

Future<void> tick() => Future<void>.delayed(Duration.zero);

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
      for (var i = 0; i < 10; i++) {
        await tick();
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
      await tick();
      expect(app.catalogState(ContentType.live).phase, CatalogLoadPhase.ready);
      expect(app.channelsOf(ContentType.live), hasLength(1));
      expect(
        app.catalogState(ContentType.movie).phase,
        CatalogLoadPhase.loading,
      );
      expect(app.isLoading, true);
      api.movies.complete([]);
      await tick();
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
      await tick();
      api.movies.completeError(Exception('offline'));
      await tick();
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
    await tick();
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
    api.live.complete([]);
    api.movies.complete([]);
    api.series.complete([]);
    await tester.pump();
    await loading;
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byTooltip('Diretta: Pronta'), findsOneWidget);
    expect(tester.getSize(find.byType(Row).first), before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    // Allow the pre-existing kids-cache notification debounce to finish.
    await tester.pump(const Duration(milliseconds: 300));
  });
}
