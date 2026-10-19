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
    expect(ui.homePosterShape, HomePosterShape.landscape);
    expect(ui.homeRecentShape, HomePosterShape.landscape);
    expect(ui.homePosterDensity, HomeDensity.automatic);
    expect(ui.homeRecentDensity, HomeDensity.automatic);
    expect(ui.homeRecommendationLimit, 10);
    expect(ui.homeRecentLimit, 50);
    expect(ui.homeBannerSize, HomeBannerSize.large);
    expect(ui.homeOverview, isTrue);
    expect(ui.uiScalePercent, 100);
    expect(ui.viewMode, CatalogViewMode.landscape);
    expect(ui.compact, isFalse);
    ui.dispose();
  });

  test('Playlist and guide refresh once a day by default', () async {
    expect(await PlaylistRefreshService(() async {}).loadIntervalMinutes(), 1440);
    expect(await EpgService().intervalMinutes(), 1440);
  });

  test('A chosen playlist interval is kept', () async {
    final s = PlaylistRefreshService(() async {});
    await s.saveIntervalMinutes(PlaylistRefreshInterval.weekly.minutes);
    expect(await s.loadIntervalMinutes(), 10080);
    s.stop();
  });
}
