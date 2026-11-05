import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/tmdb_item.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/screens/catalog_page.dart';
import 'package:stellar_tv/services/catalog_builder.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/widgets/catalog_layouts.dart';
import 'package:stellar_tv/widgets/poster_card.dart';

/// The catalog poster options apply to every layout that shows posters.
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

  for (final tv in [false, true]) {
    test('without titles a grid cell is exactly a poster (tv: $tv)', () async {
      await device(tv: tv);
      final withTitles = channelGridDelegate(ContentType.movie);
      final posterOnly = channelGridDelegate(
        ContentType.movie,
        showTitles: false,
      );
      expect(posterOnly.childAspectRatio, closeTo(2 / 3, 1e-9));
      // With titles the cell is taller than the poster, for the caption.
      expect(withTitles.childAspectRatio, lessThan(2 / 3));
      // Same columns either way, so the remote keeps its grid.
      expect(posterOnly.maxCrossAxisExtent, withTitles.maxCrossAxisExtent);
      // Live channels always keep their name.
      expect(
        channelGridDelegate(ContentType.live, showTitles: false),
        isA<SliverGridDelegateWithMaxCrossAxisExtent>().having(
          (d) => d.childAspectRatio,
          'ratio',
          channelGridDelegate(ContentType.live).childAspectRatio,
        ),
      );
    });
  }

  Future<UiSettings> settings() async {
    SharedPreferences.setMockInitialValues({});
    final ui = UiSettings();
    await ui.load();
    await ui.setShowRatings(false);
    return ui;
  }

  Widget host(
    UiSettings ui,
    Widget child, {
    Size size = const Size(200, 360),
  }) => ChangeNotifierProvider.value(
    value: ui,
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox.fromSize(size: size, child: child),
        ),
      ),
    ),
  );

  testWidgets('Preferiti grid follows titles and ratings options', (
    tester,
  ) async {
    await device(tv: false);
    final ui = await settings();
    const item = TmdbItem(
      id: 1,
      mediaType: 'movie',
      title: 'Titolo di prova',
      overview: '',
      posterPath: null,
      backdropPath: null,
      voteAverage: 7.5,
      popularity: 1,
      releaseDate: '',
    );
    await tester.pumpWidget(
      host(
        ui,
        TmdbPosterCard(item: item, width: double.infinity, onTap: () {}),
      ),
    );
    expect(find.text('Titolo di prova'), findsOneWidget);
    expect(find.byType(RatingBadge), findsNothing);
    await ui.setShowTitles(false);
    await tester.pump();
    expect(find.text('Titolo di prova'), findsNothing);
  });

  testWidgets('Panoramica follows the quality labels option', (tester) async {
    await device(tv: false);
    final ui = await settings();
    final channel = Channel(
      id: 'm1',
      name: 'Prova 4K',
      url: 'https://example.invalid/m1.mp4',
      logo: '',
      group: 'Azione',
      type: ContentType.movie,
    );
    await tester.pumpWidget(
      host(
        ui,
        CatalogLandscapeCard(
          entry: CatalogEntry(primary: channel, variants: [channel]),
          isFavorite: false,
          onTap: () {},
          onFavoriteTap: () {},
        ),
        // A Panoramica cell on a phone: 16:9 at the default width.
        size: const Size(340, 340 * 9 / 16),
      ),
    );
    expect(find.text('4K'), findsOneWidget);
    await ui.setShowQuality(false);
    await tester.pump();
    expect(find.text('4K'), findsNothing);
  });

  testWidgets('poster corners follow the chosen style and persist', (
    tester,
  ) async {
    await device(tv: false);
    final ui = await settings();
    const item = TmdbItem(
      id: 2,
      mediaType: 'movie',
      title: 'Angoli',
      overview: '',
      posterPath: null,
      backdropPath: null,
      voteAverage: 7,
      popularity: 1,
      releaseDate: '',
    );
    await tester.pumpWidget(
      host(
        ui,
        TmdbPosterCard(item: item, width: double.infinity, onTap: () {}),
      ),
    );
    BorderRadiusGeometry? clip() =>
        tester.widget<ClipRRect>(find.byType(ClipRRect).first).borderRadius;
    expect(clip(), BorderRadius.circular(10));
    await ui.setPosterCorners(PosterCorners.rounded);
    await tester.pump();
    expect(clip(), BorderRadius.circular(20));
    await ui.setPosterCorners(PosterCorners.square);
    await tester.pump();
    expect(clip(), BorderRadius.circular(3));

    // A fresh load (another start, or settings from the cloud) keeps it.
    final reloaded = UiSettings();
    await reloaded.load();
    expect(reloaded.posterCorners, PosterCorners.square);
    expect(PosterCornersInfo.parse('unknown'), PosterCorners.standard);
  });
}
