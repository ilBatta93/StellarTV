import 'package:stellar_tv/widgets/poster_card.dart';
import 'dart:io';
import 'dart:ui' as image_ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stellar_tv/widgets/tv_focusable.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/history_entry.dart';
import 'package:stellar_tv/models/tmdb_item.dart';
import 'package:stellar_tv/models/user_profile.dart';
import 'package:stellar_tv/providers/app_provider.dart';
import 'package:stellar_tv/providers/discover_provider.dart';
import 'package:stellar_tv/providers/history_provider.dart';
import 'package:stellar_tv/providers/profile_provider.dart';
import 'package:stellar_tv/providers/reactions_provider.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/screens/discover_page.dart';
import 'package:stellar_tv/services/profile_service.dart';
import 'package:stellar_tv/services/sync_service.dart';
import 'package:stellar_tv/services/tmdb_service.dart';
import 'package:stellar_tv/theme/app_theme.dart';
import 'october_live_multiview_test.dart' as fixtures;

TmdbItem item(int id, String title) => TmdbItem(
  id: id,
  mediaType: 'movie',
  title: title,
  overview: 'Descrizione del film riprodotto di recente',
  posterPath: null,
  backdropPath: null,
  voteAverage: 8,
  popularity: 2,
  releaseDate: '2025-01-01',
);

class HomeApp extends fixtures.TestApp {
  @override
  bool isAvailable(TmdbItem item) => true;
  @override
  bool isTmdbAllowed(TmdbItem item) => true;
  @override
  Channel? findForTmdb(TmdbItem item) => null;
}

class FakeTmdb extends TmdbService {
  int calls = 0;
  @override
  Future<String?> titleLogo(TmdbItem item) async => null;
  @override
  Future<TmdbItem?> homeArtwork(String title, {required bool isMovie}) async =>
      null;
  @override
  Future<TmdbItem?> findByTitle(String title, {required bool isMovie}) async {
    calls++;
    return item(77, title);
  }
}

class HomeDiscover extends DiscoverProvider {
  HomeDiscover(super.tmdb);
  @override
  bool get hasData => true;
  @override
  List<TmdbItem> get topMovies => [
    item(1, 'Titolo Top uno'),
    item(2, 'Titolo Top due'),
  ];
  @override
  List<TmdbItem> get topSeries => [item(3, 'Titolo serie uno')];
  @override
  Future<void> loadForYou(
    List<Channel> history, {
    List<TmdbItem> liked = const [],
    Set<String> disliked = const {},
    String reactionSignature = '',
  }) async {}
}

class HomeHistory extends HistoryProvider {
  HomeHistory(super.sync);
  @override
  List<HistoryEntry> get entries => [
    fixtures.history('ultima visione', 12, ContentType.movie),
  ];
  @override
  List<HistoryEntry> get continueWatching => [
    fixtures
        .history('vecchia visione', 9, ContentType.movie)
        .copyWith(position: const Duration(minutes: 10)),
  ];
}

class HomeProfile extends ProfileProvider {
  HomeProfile(super.service, super.sync);
  @override
  UserProfile? get selected => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  fixtures.mainSetupForRemote();
  setUp(() async {
    for (final family in ['Sora', 'Manrope', 'MaterialIcons']) {
      final loader = FontLoader(family)
        ..addFont(
          rootBundle.load(
            family == 'MaterialIcons'
                ? 'fonts/MaterialIcons-Regular.otf'
                : 'assets/fonts/$family.ttf',
          ),
        );
      await loader.load();
    }
  });
  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    testWidgets(
      'Home latest history banner and row header intact ${size.width}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = SupabaseClient('https://example.invalid', 'test');
        final sync = SyncService(client);
        final app = HomeApp(), tmdb = FakeTmdb();
        final discover = HomeDiscover(tmdb);
        final history = HomeHistory(sync);
        final profile = HomeProfile(ProfileService(client), sync);
        final reactions = ReactionsProvider();
        final settings = UiSettings();
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          MultiProvider(
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
              home: Scaffold(
                body: RepaintBoundary(
                  key: boundaryKey,
                  child: const DiscoverPage(),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Titolo ultima visione'), findsOneWidget);

        final title = tester.getRect(
          find.byKey(const ValueKey('tv-home-banner-title')),
        );
        expect(title.top, greaterThanOrEqualTo(0));
        expect(title.bottom, lessThan(size.height));
        expect(find.text('★ 8.0'), findsNothing);
        expect(tmdb.calls, 1);
        discover.notifyListeners();
        await tester.pump(const Duration(milliseconds: 500));
        expect(tmdb.calls, 1);
        final boundary = boundaryKey.currentContext?.findRenderObject();
        if (boundary is RenderRepaintBoundary) {
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: image_ui.ImageByteFormat.png,
            );
            if (bytes != null) {
              await Directory('/tmp/stv').create(recursive: true);
              await File(
                '/tmp/stv/home-${size.width.toInt()}.png',
              ).writeAsBytes(bytes.buffer.asUint8List());
            }
            image.dispose();
          });
        }
        final top = find.ancestor(
          of: find.text('Top 10 della settimana', skipOffstage: false),
          matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_TvTopRow',
            skipOffstage: false,
          ),
        );
        final poster = find
            .descendant(
              of: top,
              matching: find.byWidgetPredicate(
                (w) => w is RankedPosterCard,
                skipOffstage: false,
              ),
              skipOffstage: false,
            )
            .first;
        final stop = find
            .descendant(
              of: poster,
              matching: find.byType(TvFocusable, skipOffstage: false),
              skipOffstage: false,
            )
            .first;
        Focus.of(
          tester.element(
            find
                .descendant(
                  of: stop,
                  matching: find.byType(RepaintBoundary, skipOffstage: false),
                  skipOffstage: false,
                )
                .first,
          ),
        ).parent?.requestFocus();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        final header = tester.getRect(find.text('Top 10 della settimana'));
        expect(header.top, greaterThanOrEqualTo(170));
        expect(header.bottom, lessThan(size.height));
        expect(tester.takeException(), isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'top movies');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
        history.dispose();
        discover.dispose();
        profile.dispose();
        reactions.dispose();
        settings.dispose();
        app.dispose();
        client.auth.stopAutoRefresh();
        await tester.pump(const Duration(seconds: 3));
      },
    );
  }
}
