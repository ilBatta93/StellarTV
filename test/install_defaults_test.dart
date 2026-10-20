import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/home_layout_preferences.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/services/epg_service.dart';
import 'package:stellar_tv/services/playlist_refresh_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Fresh install uses the chosen Home and catalog defaults', () async {
    final ui = UiSettings();
    await ui.load();
    expect(ui.watchedPercent, 94);
    expect(ui.homePosterShape, HomePosterShape.portrait);
    expect(ui.homeRecentShape, HomePosterShape.portrait);
    expect(ui.homePosterDensity, HomeDensity.automatic);
    expect(ui.homeRecentDensity, HomeDensity.automatic);
    expect(ui.homeRecommendationLimit, 10);
    expect(ui.homeRecentLimit, 50);
    expect(ui.homeBannerSize, HomeBannerSize.compact);
    expect(ui.homeOverview, isTrue);
    expect(ui.homeTitles, isFalse);
    expect(ui.homeRecentTitles, isFalse);
    expect(ui.uiScalePercent, 100);
    expect(ui.compact, isFalse);
    expect(ui.showPosters, isTrue);
    expect(ui.showTitles, isTrue);
    expect(ui.showRatings, isTrue);
    expect(ui.showQuality, isTrue);
    expect(ui.startSection, AppSection.home);
    ui.dispose();
  });

  test('Fresh install uses Poster catalog layout', () async {
    final ui = UiSettings();
    expect(ui.viewMode, CatalogViewMode.grid);
    await ui.load();
    expect(ui.viewMode, CatalogViewMode.grid);
    ui.dispose();
  });

  test('Fresh install uses Grande catalog posters', () async {
    final ui = UiSettings();
    expect(ui.gridSize, 'grande');
    await ui.load();
    expect(ui.gridSize, 'grande');
    ui.dispose();
  });

  test('Saved catalog preferences are not overwritten on upgrade', () async {
    SharedPreferences.setMockInitialValues({
      'ui_catalog_view': 'landscape',
      'ui_grid_size': 'piccola',
      'ui_watched_percent': 95,
    });
    final ui = UiSettings();
    await ui.load();
    expect(ui.viewMode, CatalogViewMode.landscape);
    expect(ui.gridSize, 'piccola');
    expect(ui.watchedPercent, 95);
    ui.dispose();
  });

  test('Appearance reset restores Poster layout and Grande posters', () async {
    SharedPreferences.setMockInitialValues({
      'ui_catalog_view': 'landscape',
      'ui_grid_size': 'piccola',
      'player_settings_v1': 'local',
    });
    final ui = UiSettings();
    await ui.load();
    await ui.resetAppearance();
    expect(ui.viewMode, CatalogViewMode.grid);
    expect(ui.gridSize, 'grande');
    expect(
      (await SharedPreferences.getInstance()).getString('player_settings_v1'),
      'local',
    );
    ui.dispose();
  });

  test('Playlist and guide refresh once a day by default', () async {
    expect(
      await PlaylistRefreshService(() async {}).loadIntervalMinutes(),
      1440,
    );
    expect(await EpgService().intervalMinutes(), 1440);
  });

  test('A chosen playlist interval is kept', () async {
    final s = PlaylistRefreshService(() async {});
    await s.saveIntervalMinutes(PlaylistRefreshInterval.weekly.minutes);
    expect(await s.loadIntervalMinutes(), 10080);
    s.stop();
  });
}
