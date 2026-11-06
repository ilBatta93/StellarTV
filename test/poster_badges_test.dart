import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/poster_badges.dart';
import 'package:stellar_tv/models/tmdb_item.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/screens/catalog_page.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/widgets/awards_row.dart';
import 'package:stellar_tv/widgets/channel_card.dart';
import 'package:stellar_tv/widgets/home_art.dart';
import 'package:stellar_tv/widgets/poster_card.dart';
import 'package:stellar_tv/widgets/poster_overlay.dart';

/// Configurable poster badges, each in its own fixed place.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> device({required bool tv}) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('stellartv/device'),
          (_) async => tv,
        );
    await DeviceTypeService.initialize();
  }

  Future<UiSettings> settings() async {
    SharedPreferences.setMockInitialValues({});
    final ui = UiSettings();
    await ui.load();
    return ui;
  }

  void expectApart(WidgetTester tester, Finder a, Finder b) {
    final ra = tester.getRect(a);
    final rb = tester.getRect(b);
    expect(
      ra.intersect(rb).isEmpty || ra.intersect(rb).width <= 0,
      isTrue,
      reason: '$ra overlaps $rb',
    );
    expect(ra.overlaps(rb), isFalse, reason: '$ra overlaps $rb');
  }

  test('rating source picks the score to show', () {
    // Automatic: IMDb; TMDB only once IMDb confirmed it has none.
    expect(ratingFor(RatingSource.auto, null, 7.5).value, 0);
    expect(ratingFor(RatingSource.auto, 8.1, 7.5), (value: 8.1, imdb: true));
    expect(ratingFor(RatingSource.auto, 0, 7.5), (value: 7.5, imdb: false));
    // Only IMDb never falls back.
    expect(ratingFor(RatingSource.imdb, 0, 7.5).value, 0);
    expect(ratingFor(RatingSource.imdb, 8.1, 7.5).value, 8.1);
    // Only TMDB does not wait for IMDb.
    expect(ratingFor(RatingSource.tmdb, null, 7.5), (value: 7.5, imdb: false));
    expect(ratingFor(RatingSource.tmdb, 8.1, 0).value, 0);
    expect(RatingSource.parse('tmdb'), RatingSource.tmdb);
    expect(RatingSource.parse('???'), RatingSource.auto);
  });

  test('«Nuovo» lasts a fixed number of days', () {
    final now = DateTime(2026, 11, 6, 12);
    int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch ~/ 1000;
    expect(isRecentlyAdded(ago(const Duration(days: 1)), now), isTrue);
    expect(
      isRecentlyAdded(ago(const Duration(days: newBadgeDays - 1)), now),
      isTrue,
    );
    expect(
      isRecentlyAdded(ago(const Duration(days: newBadgeDays)), now),
      isFalse,
    );
    expect(isRecentlyAdded(0, now), isFalse);
    // A source clock in the future does not mark everything as new.
    expect(isRecentlyAdded(ago(const Duration(days: -3)), now), isFalse);
  });

  test('title placement and badges persist', () async {
    final ui = await settings();
    expect(ui.titlePlacement, TitlePlacement.below);
    expect(ui.badgeNew, isFalse);
    expect(ui.badgePlatform, isFalse);
    await ui.setTitlePlacement(TitlePlacement.overlay);
    await ui.setRatingSource(RatingSource.imdb);
    await ui.setBadgeNew(true);
    await ui.setBadgePlatform(true);
    final again = UiSettings();
    await again.load();
    expect(again.titlePlacement, TitlePlacement.overlay);
    expect(again.titlesBelow, isFalse);
    expect(again.showTitles, isTrue);
    expect(again.ratingSource, RatingSource.imdb);
    expect(again.badgeNew, isTrue);
    expect(again.badgePlatform, isTrue);
    await again.setTitlePlacement(TitlePlacement.hidden);
    expect(again.showTitles, isFalse);
    await again.resetAppearance();
    expect(again.titlePlacement, TitlePlacement.below);
    expect(again.ratingSource, RatingSource.auto);
  });

  for (final tv in [false, true]) {
    test('titles on the poster keep a poster-shaped cell (tv: $tv)', () async {
      await device(tv: tv);
      final overlay = channelGridDelegate(ContentType.movie, showTitles: false);
      expect(overlay.childAspectRatio, closeTo(2 / 3, 1e-9));
    });
  }

  Widget host(UiSettings ui, Widget child, {double w = 140, double h = 260}) =>
      ChangeNotifierProvider.value(
        value: ui,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: w, height: h, child: child),
            ),
          ),
        ),
      );

  final movie = TmdbItem(
    id: 11,
    mediaType: 'movie',
    title: 'Titolo premiato',
    overview: '',
    posterPath: null,
    backdropPath: null,
    voteAverage: 7.4,
    popularity: 1,
    releaseDate: '',
  );

  for (final tv in [false, true]) {
    testWidgets('the award trophy sits under the score, never on it '
        '(tv: $tv)', (tester) async {
      await device(tv: tv);
      final ui = await settings();
      // TMDB shows the score at once, so both badges are on screen.
      await ui.setRatingSource(RatingSource.tmdb);
      await tester.pumpWidget(
        host(
          ui,
          TmdbPosterCard(
            item: movie,
            width: 96,
            onTap: () {},
            badges: const [AwardWinnerBadge()],
          ),
          w: 96,
        ),
      );
      final score = find.text('7.4');
      final trophy = find.byType(AwardWinnerBadge);
      expect(score, findsOneWidget);
      expect(trophy, findsOneWidget);
      expectApart(tester, score, trophy);
      expect(
        tester.getTopLeft(trophy).dy,
        greaterThan(tester.getTopLeft(score).dy),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('catalog card: badges in their corners, title on the poster', (
    tester,
  ) async {
    await device(tv: false);
    final ui = await settings();
    await ui.setBadgeNew(true);
    await ui.setTitlePlacement(TitlePlacement.overlay);
    final added = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 3600;
    final channel = Channel(
      id: 'n1',
      name: 'Titolo nuovo',
      url: 'http://example.test/n1',
      logo: '',
      group: 'Prova',
      type: ContentType.movie,
      addedAt: added,
    );
    await tester.pumpWidget(
      host(
        ui,
        ChannelCard(
          channel: channel,
          isFavorite: true,
          onTap: () {},
          onFavoriteTap: () {},
          qualityLabel: '4K',
        ),
        h: 210,
      ),
    );
    final poster = tester.getRect(find.byType(PosterOverlay));
    final title = find.text('Titolo nuovo');
    expect(title, findsOneWidget);
    // On the poster, not under it.
    expect(poster.contains(tester.getCenter(title)), isTrue);
    final badgeNew = find.text('NUOVO');
    final quality = find.text('4K');
    final heart = find.byIcon(Icons.favorite_rounded);
    expectApart(tester, badgeNew, heart);
    expectApart(tester, quality, title);
    // Top left, top right, bottom left above the title.
    expect(tester.getCenter(badgeNew).dx, lessThan(poster.center.dx));
    expect(tester.getCenter(heart).dx, greaterThan(poster.center.dx));
    expect(
      tester.getBottomLeft(quality).dy,
      lessThanOrEqualTo(tester.getTopLeft(title).dy),
    );
    expect(tester.takeException(), isNull);

    await ui.setTitlePlacement(TitlePlacement.below);
    await tester.pump();
    final shorter = tester.getRect(find.byType(PosterOverlay));
    expect(shorter.height, lessThan(poster.height));
    expect(shorter.contains(tester.getCenter(title)), isFalse);
  });

  testWidgets('Home card: score, rank and progress never cover each other', (
    tester,
  ) async {
    await device(tv: false);
    final ui = await settings();
    await tester.pumpWidget(
      host(
        ui,
        HomeLandscapeCard(
          title: 'Titolo',
          image: null,
          onTap: () {},
          rank: 3,
          rating: 8.2,
          progress: 0.4,
        ),
        w: 208,
        h: 220,
      ),
    );
    expectApart(tester, find.text('#3'), find.text('40%'));
    expectApart(tester, find.text('#3'), find.text('8.2'));
    expect(tester.takeException(), isNull);
  });
}
