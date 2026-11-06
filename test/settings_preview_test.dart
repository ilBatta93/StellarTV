import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/banner_trailer.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/home_layout_preferences.dart';
import 'package:stellar_tv/models/poster_badges.dart';
import 'package:stellar_tv/models/poster_focus.dart';
import 'package:stellar_tv/models/settings_preview_zone.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/screens/settings_preview.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/theme/app_theme.dart';
import 'package:stellar_tv/widgets/channel_card.dart';
import 'package:stellar_tv/widgets/poster_card.dart';
import 'package:stellar_tv/widgets/tv_focusable.dart';

/// The settings preview: a copy that never saves, zones, the real cards
/// drawn with the values being looked at, trials and "Prima/Dopo".
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

  tearDown(() => device(tv: false));

  /// Every saved look-and-feel value away from its default.
  Future<UiSettings> changedSettings() async {
    SharedPreferences.setMockInitialValues({});
    final ui = UiSettings();
    await ui.load();
    await ui.setWatchedPercent(80);
    await ui.setAccent('viola');
    await ui.setGridSize('piccola');
    await ui.setShowPosters(false);
    await ui.setAnimations(false);
    await ui.setCompact(true);
    await ui.setCatalogViewMode(CatalogViewMode.list);
    await ui.setCatalogViewMode(CatalogViewMode.wall, type: ContentType.series);
    await ui.moveSection(0, 2);
    await ui.setStartSection(AppSection.movies);
    await ui.setTextScale('grande');
    await ui.setShowRatings(false);
    await ui.setShowQuality(false);
    await ui.setTitlePlacement(TitlePlacement.overlay);
    await ui.setFocusGlow(false);
    await ui.setFavoriteHeart(false);
    await ui.setLiveNumbers(true);
    await ui.setLivePreview(false);
    await ui.setPosterCorners(PosterCorners.values.last);
    await ui.setPosterProgress(false);
    await ui.setPosterDetails(true);
    await ui.setSceneArt(true);
    await ui.setTitleLogos(true);
    await ui.setFocusZoom(PosterFocusZoom.wide);
    await ui.setFocusRing(PosterFocusRing.thick);
    await ui.setFocusScene(true);
    await ui.setFocusSceneLogo(false);
    await ui.setFocusSceneDetails(false);
    await ui.setFocusSceneEpisode(false);
    await ui.setFocusSceneBadges(false);
    await ui.setBannerTrailer(BannerTrailerMode.values.last);
    await ui.setBannerTrailerAudio(BannerTrailerAudio.values.first);
    await ui.setBannerTrailerDelay(bannerTrailerDelays.last);
    await ui.setRatingSource(RatingSource.values.last);
    await ui.setBadgeNew(true);
    await ui.setBadgePlatform(true);
    await ui.setGridColumns(UiSettings.gridColumnChoices().last);
    await ui.setHomePosterShape(HomePosterShape.landscape);
    await ui.setHomeRecentShape(HomePosterShape.square);
    await ui.setHomePosterDensity(HomeDensity.dense);
    await ui.setHomeRecentDensity(HomeDensity.spacious);
    await ui.setHomeRecommendationLimit(
      HomeLayoutPolicy.recommendationLimits.last,
    );
    await ui.setHomeRecentLimit(HomeLayoutPolicy.itemLimits.first);
    await ui.setHomeBannerSize(HomeBannerSize.large);
    await ui.setHomeBannerSource(HomeBannerSource.forYou);
    await ui.setHomeOverview(false);
    await ui.setHomeTitles(true);
    await ui.setHomeRecentTitles(true);
    await ui.setUiScale(HomeLayoutPolicy.uiScales.first);
    await ui.setHomeRowOrder(const ['b', 'a']);
    await ui.setHomeRowVisible('c', false);
    return ui;
  }

  test('the preview copy carries every saved value', () async {
    final ui = await changedSettings();
    final copy = ui.previewCopy();
    expect(copy.signature, ui.signature);
    expect(copy.persist, isFalse);
    expect(UiSettings().signature, isNot(ui.signature));
  });

  test('the preview copy never saves nor recolors the app', () async {
    SharedPreferences.setMockInitialValues({});
    final ui = UiSettings();
    await ui.load();
    final accent = AppColors.primary;
    final copy = ui.previewCopy();
    await copy.setHomePosterShape(HomePosterShape.square);
    await copy.setAccent('verde');
    await copy.setSectionOrder(AppSection.values.reversed.toList());
    await copy.resetSectionLayout();
    await copy.resetAppearance();
    expect(copy.homePosterShape, HomePosterShape.square);
    expect(AppColors.primary, accent);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
    expect(ui.homePosterShape, HomePosterShape.portrait);
  });

  test('zones: badge corners sit on the poster picture', () {
    const card = Rect.fromLTWH(0, 0, 100, 190);
    final picture = posterPictureOf(card);
    expect(picture.height, 150);
    expect(PreviewZone.posterTopLeft.cornerOf(picture)!.top, 0);
    expect(PreviewZone.posterTopRight.cornerOf(picture)!.right, 100);
    expect(PreviewZone.posterBottom.cornerOf(picture)!.bottom, 150);
    expect(PreviewZone.banner.cornerOf(picture), isNull);
    expect(PreviewZone.homePage.whole, isTrue);
    expect(PreviewZone.recent.whole, isFalse);
    expect(PreviewZone.catalogSeries.surface, PreviewSurface.catalog);
  });

  test('trial, "Prima" and zones in the controller', () async {
    SharedPreferences.setMockInitialValues({});
    final ui = UiSettings();
    await ui.load();
    final c = SettingsPreviewController(ui);
    expect(c.changed, isFalse);
    c.showBefore(true);
    expect(c.showingBefore, isFalse, reason: 'nothing to compare yet');

    await c.tryOption((s) => s.setHomeTitles(true));
    expect(c.trying, isTrue);
    expect(c.shown.homeTitles, isTrue);
    expect(ui.homeTitles, isFalse, reason: 'a trial is not saved');
    c.endTrial();
    expect(c.shown.homeTitles, isFalse);

    await ui.setHomeTitles(true);
    expect(c.changed, isTrue);
    c.showBefore(true);
    expect(c.shown.homeTitles, isFalse, reason: 'values at opening');
    c.showBefore(false);
    expect(c.shown, same(ui));

    c.point(PreviewZone.catalogSeries);
    expect(c.surface, PreviewSurface.catalog);
    expect(c.catalogType, ContentType.series);
    c.point(null);
    expect(c.surface, PreviewSurface.catalog, reason: 'stays put');
    c.dispose();
  });

  Future<(UiSettings, SettingsPreviewController)> pumpPreview(
    WidgetTester tester, {
    PreviewZone? zone,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final ui = UiSettings();
    await ui.load();
    final controller = SettingsPreviewController(ui)..point(zone);
    await tester.pumpWidget(
      ChangeNotifierProvider<UiSettings>.value(
        value: ui,
        child: MaterialApp(
          home: Scaffold(
            body: SettingsPreviewLayout(
              controller: controller,
              list: ListView(
                children: [
                  for (final z in [
                    PreviewZone.banner,
                    PreviewZone.recent,
                    PreviewZone.catalogPage,
                  ])
                    PreviewTarget(
                      zone: z,
                      child: SizedBox(
                        height: 200,
                        child: Text(z.label, key: ValueKey(z)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return (ui, controller);
  }

  testWidgets('phone: the real Home cards follow the shown values', (
    tester,
  ) async {
    final (ui, controller) = await pumpPreview(tester);
    expect(find.byType(TmdbPosterCard), findsWidgets);
    expect(find.text('Consigliati per te'), findsOneWidget);
    double width() => tester.getSize(find.byType(TmdbPosterCard).first).width;
    double height() => tester.getSize(find.byType(TmdbPosterCard).first).height;
    final portrait = width() / height();

    await controller.tryOption(
      (s) => s.setHomePosterShape(HomePosterShape.landscape),
    );
    await tester.pump();
    await tester.pump();
    expect(width() / height(), greaterThan(portrait * 2));
    expect(find.textContaining('Prova'), findsOneWidget);

    controller.endTrial();
    await tester.pump();
    expect(width() / height(), closeTo(portrait, 0.05));

    await ui.setHomePosterShape(HomePosterShape.square);
    await tester.pump();
    expect(find.text('Prima'), findsOneWidget);
    expect(find.text('Dopo'), findsOneWidget);
    await tester.tap(find.text('Prima'));
    await tester.pump();
    await tester.pump();
    expect(width() / height(), closeTo(portrait, 0.05));
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('touching a setting points the preview at its zone', (
    tester,
  ) async {
    final (_, controller) = await pumpPreview(tester);
    await tester.ensureVisible(find.byKey(const ValueKey(PreviewZone.recent)));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey(PreviewZone.recent)));
    await tester.pump();
    expect(controller.zone, PreviewZone.recent);
    expect(find.textContaining('Viste di recente'), findsWidgets);

    await tester.ensureVisible(
      find.byKey(const ValueKey(PreviewZone.catalogPage)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey(PreviewZone.catalogPage)));
    await tester.pump();
    await tester.pump();
    expect(controller.surface, PreviewSurface.catalog);
    expect(find.byType(ChannelCard), findsWidgets);
    expect(find.byType(PosterProgressSample), findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('scrolling the list moves the preview along', (tester) async {
    final (_, controller) = await pumpPreview(tester);
    await tester.drag(
      find.byKey(const ValueKey(PreviewZone.banner)),
      const Offset(0, -250),
    );
    await tester.pump();
    expect(controller.zone, PreviewZone.recent);
    controller.dispose();
  });

  testWidgets('TV: the focus zone shows the focus look on a poster', (
    tester,
  ) async {
    await device(tv: true);
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final (_, controller) = await pumpPreview(tester, zone: PreviewZone.focus);
    expect(find.byType(PreviewFocused), findsOneWidget);
    expect(find.text('Locandina selezionata'), findsNothing);
    expect(find.textContaining('Locandina selezionata'), findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('pickWithPreview: a tap tries, Applica saves', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final ui = UiSettings();
    await ui.load();
    final controller = SettingsPreviewController(ui);
    await tester.pumpWidget(
      ChangeNotifierProvider<UiSettings>.value(
        value: ui,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => pickWithPreview<HomeBannerSize>(
                  context,
                  controller: controller,
                  title: 'Dimensione banner',
                  options: HomeBannerSize.values,
                  current: ui.homeBannerSize,
                  label: (v) => v.label,
                  apply: (s, v) => s.setHomeBannerSize(v),
                ),
                child: const Text('apri'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grande'));
    await tester.pump();
    expect(controller.shown.homeBannerSize, HomeBannerSize.large);
    expect(ui.homeBannerSize, HomeBannerSize.compact);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(controller.trying, isFalse);
    expect(ui.homeBannerSize, HomeBannerSize.compact);

    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bilanciato'));
    await tester.tap(find.text('Applica'));
    await tester.pumpAndSettle();
    expect(ui.homeBannerSize, HomeBannerSize.balanced);
    controller.dispose();
  });
}
