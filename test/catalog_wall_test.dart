import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/screens/catalog_page.dart';
import 'package:stellar_tv/services/catalog_builder.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/widgets/catalog_layouts.dart';
import 'package:stellar_tv/widgets/channel_card.dart';
import 'package:stellar_tv/widgets/poster_overlay.dart';
import 'package:stellar_tv/widgets/title_facets.dart';

/// "Muro": a wall of covers only, 2 px apart, one column denser than
/// "Poster"; on TV a fixed strip names the focused title.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> device({required bool tv}) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('stellartv/device'),
          (call) async => call.method == 'isTv' ? tv : null,
        );
    await DeviceTypeService.initialize();
  }

  Future<UiSettings> settings() async {
    SharedPreferences.setMockInitialValues({});
    final ui = UiSettings();
    await ui.load();
    return ui;
  }

  tearDown(() => device(tv: false));

  final channel = Channel(
    id: 'w1',
    name: 'Titolo del muro (2019)',
    url: 'http://example.test/w1',
    logo: '',
    group: 'Prova',
    type: ContentType.movie,
    addedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 3600,
  );

  test('is a layout of its own and is remembered', () async {
    final ui = await settings();
    expect(CatalogViewMode.wall.label, 'Muro');
    expect(CatalogViewMode.values, contains(CatalogViewMode.wall));
    await ui.setCatalogViewMode(CatalogViewMode.wall, type: ContentType.movie);
    final again = UiSettings();
    await again.load();
    expect(again.viewModeFor(ContentType.movie), CatalogViewMode.wall);
  });

  for (final tv in [false, true]) {
    test('one column more than Poster, 2 px apart (tv: $tv)', () async {
      await device(tv: tv);
      const width = 1000.0;
      final poster = gridColumnCount(
        channelGridDelegate(ContentType.movie, showTitles: false),
        width,
      );
      final wall = wallGridDelegate(ContentType.movie, width: width);
      expect(wall.columns, poster + 1);
      expect(wall.crossAxisSpacing, 2);
      expect(wall.mainAxisSpacing, 2);
      expect(wall.childAspectRatio, closeTo(2 / 3, 1e-9));
      expect(
        wall.maxCrossAxisExtent,
        closeTo((width - 2 * (wall.columns - 1)) / wall.columns, 1e-6),
      );
    });
  }

  test('fixed columns win over the denser default', () {
    final wall = wallGridDelegate(ContentType.series, width: 400, columns: 3);
    expect(wall.columns, 3);
    expect(gridColumnCount(wall, 400), 3);
  });

  testWidgets('covers only: no title, rating or badges', (tester) async {
    await device(tv: false);
    final ui = await settings();
    await ui.setBadgeNew(true);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: ui,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                height: 180,
                child: ChannelCard(
                  channel: channel,
                  isFavorite: true,
                  onTap: () {},
                  onFavoriteTap: () {},
                  qualityLabel: '4K',
                  bare: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(ChannelRatingBadge), findsNothing);
    expect(find.byType(PosterNewBadge), findsNothing);
    expect(find.text('4K'), findsNothing);
    expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    // The progress marks stay.
    expect(find.byType(PosterProgressMark), findsNWidgets(2));
    // No title line: the cover fills the whole cell.
    expect(tester.getSize(find.byType(PosterOverlay)).height, closeTo(180, 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV strip names the focused title with its year', (tester) async {
    await device(tv: true);
    final ui = await settings();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: ui,
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const Expanded(child: SizedBox()),
                CatalogWallStrip(
                  entry: CatalogEntry(primary: channel, variants: [channel]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text(channel.displaySeriesName), findsOneWidget);
    expect(find.text('2019'), findsOneWidget);
    expect(find.byType(ChannelRatingBadge), findsOneWidget);
    expect(
      tester.getSize(find.byType(CatalogWallStrip)).height,
      CatalogWallStrip.height,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty strip keeps its height', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Column(children: [CatalogWallStrip(entry: null)])),
      ),
    );
    expect(
      tester.getSize(find.byType(CatalogWallStrip)).height,
      CatalogWallStrip.height,
    );
  });
}
