import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/tmdb_item.dart';
import 'package:stellar_tv/providers/discover_provider.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/services/catalog_rating_service.dart';
import 'package:stellar_tv/services/title_facet_index.dart';
import 'package:stellar_tv/services/tmdb_service.dart';
import 'package:stellar_tv/widgets/catalog_title_logo.dart';

class CountingTmdb extends TmdbService {
  final asked = <String>[];
  final result = Completer<String?>();
  @override
  Future<String?> titleLogo(TmdbItem item) {
    asked.add(item.key);
    return result.future;
  }
}

/// "Logo al posto del titolo": a logo where the catalog writes the name,
/// never one request per card.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const logo = 'https://image.tmdb.org/t/p/w500/logo.png';

  Channel movie(String id) => Channel(
    id: id,
    name: 'Titolo $id',
    url: 'http://example.test/$id',
    logo: '',
    group: 'Prova',
    type: ContentType.movie,
  );

  TmdbItem item(int id) => TmdbItem.tryParse({
    'id': id,
    'media_type': 'movie',
    'title': 'Titolo $id',
  })!;

  Future<UiSettings> settings({bool on = true}) async {
    SharedPreferences.setMockInitialValues({UiSettings.titleLogosKey: on});
    final ui = UiSettings();
    await ui.load();
    return ui;
  }

  Widget host(UiSettings ui, CountingTmdb tmdb, Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: ui),
      ChangeNotifierProvider(create: (_) => DiscoverProvider(tmdb)),
    ],
    child: MaterialApp(
      home: Scaffold(body: SizedBox(width: 300, child: child)),
    ),
  );

  CatalogTitleLogo logoOf(Channel c, {bool fetch = false}) => CatalogTitleLogo(
    channel: c,
    fetch: fetch,
    height: 40,
    fallback: Text(c.name),
  );

  /// Lets image loading and store timers finish before the test ends.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  }

  test('starts off, persists and resets', () async {
    SharedPreferences.setMockInitialValues({});
    final ui = UiSettings();
    await ui.load();
    expect(ui.titleLogos, isFalse);
    final before = ui.signature;
    await ui.setTitleLogos(true);
    expect(ui.signature, isNot(before));
    final again = UiSettings();
    await again.load();
    expect(again.titleLogos, isTrue);
    await again.resetAppearance();
    expect(again.titleLogos, isFalse);
  });

  testWidgets('a known logo replaces the written title', (tester) async {
    final c = movie('k1');
    CatalogRatingService.instance.remember(c, item(9101));
    TitleFacetIndex.instance.putLogo('movie:9101', logo, quiet: true);
    final tmdb = CountingTmdb();
    await tester.pumpWidget(host(await settings(), tmdb, logoOf(c)));
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(tmdb.asked, isEmpty);
    await settle(tester);
  });

  testWidgets('switched off, the title stays written', (tester) async {
    final c = movie('k2');
    CatalogRatingService.instance.remember(c, item(9102));
    TitleFacetIndex.instance.putLogo('movie:9102', logo, quiet: true);
    final tmdb = CountingTmdb();
    await tester.pumpWidget(
      host(await settings(on: false), tmdb, logoOf(c, fetch: true)),
    );
    expect(find.text(c.name), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(tmdb.asked, isEmpty);
  });

  testWidgets('covers ask together, once, never one request per card', (
    tester,
  ) async {
    final cards = [for (var i = 0; i < 6; i++) movie('g$i')];
    for (var i = 0; i < cards.length; i++) {
      CatalogRatingService.instance.remember(cards[i], item(9200 + i));
    }
    final batches = <List<int>>[];
    TmdbService.sharedArtworkOverride = (items) async {
      batches.add([for (final i in items) i.id]);
      return {
        'results': [
          for (final i in items)
            i.id == 9200
                ? {'tmdb_id': 9200, 'logo_path': '/logo.png'}
                : i.id == 9201
                ? {'tmdb_id': 9201, 'logo_path': null}
                : null,
        ],
      };
    };
    addTearDown(() => TmdbService.sharedArtworkOverride = null);
    final tmdb = CountingTmdb();
    await tester.pumpWidget(
      host(
        await settings(),
        tmdb,
        Column(children: [for (final c in cards) logoOf(c)]),
      ),
    );
    // The written titles stay while the batch is gathered.
    for (final c in cards) {
      expect(find.text(c.name), findsOneWidget);
    }
    await tester.pump(TmdbService.logoBatchDelay);
    await tester.pump();
    await tester.pump();
    // One shared request for all six, no single lookup.
    expect(batches, [
      [9200, 9201, 9202, 9203, 9204, 9205],
    ]);
    expect(tmdb.asked, isEmpty);
    // Only the title with a logo gets an image; the others keep the name.
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    for (final c in cards.skip(1)) {
      expect(find.text(c.name), findsOneWidget);
    }
    // Known answers are remembered: a rebuild asks nothing more.
    await tester.pumpWidget(
      host(
        await settings(),
        tmdb,
        Column(children: [for (final c in cards.take(2)) logoOf(c)]),
      ),
    );
    await tester.pump(TmdbService.logoBatchDelay);
    expect(batches, hasLength(1));
    await settle(tester);
  });

  testWidgets('one title at a time asks once, title until it arrives', (
    tester,
  ) async {
    final c = movie('f1');
    CatalogRatingService.instance.remember(c, item(9301));
    final tmdb = CountingTmdb();
    final ui = await settings();
    await tester.pumpWidget(host(ui, tmdb, logoOf(c, fetch: true)));
    expect(tmdb.asked, ['movie_9301']);
    expect(find.text(c.name), findsOneWidget);
    // Rebuilds do not ask again.
    await ui.setSceneArt(true);
    await tester.pump();
    expect(tmdb.asked, hasLength(1));
    tmdb.result.complete(logo);
    await tester.pump();
    // One frame for the future, one for the image that replaces the title.
    await tester.pump();
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    await settle(tester);
  });

  testWidgets('without a known identity nothing is asked', (tester) async {
    final tmdb = CountingTmdb();
    final c = movie('none');
    await tester.pumpWidget(
      host(await settings(), tmdb, logoOf(c, fetch: true)),
    );
    expect(tmdb.asked, isEmpty);
    expect(find.text(c.name), findsOneWidget);
  });
}
