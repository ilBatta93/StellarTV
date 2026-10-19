import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/models/home_layout_preferences.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('shape ratios preserve portrait landscape and square', () {
    expect(HomePosterShape.portrait.aspectRatio, 2 / 3);
    expect(HomePosterShape.landscape.aspectRatio, 16 / 9);
    expect(HomePosterShape.square.aspectRatio, 1);
  });
  test('item limits and UI scale reject unbounded values', () {
    expect(HomeLayoutPolicy.itemLimit(10000), 20);
    expect(HomeLayoutPolicy.itemLimit(-1, fallback: 50), 50);
    expect(HomeLayoutPolicy.uiScale(200), 100);
    expect(HomeLayoutPolicy.uiScale(90), 90);
    expect(HomeLayoutPolicy.uiScale(115), 115);
  });
  test('all shapes and densities fit their image-height budget', () {
    for (final height in [72.0, 100.0, 180.0, 260.0]) {
      for (final shape in HomePosterShape.values) {
        for (final density in HomeDensity.values) {
          final w = HomeLayoutPolicy.cardWidth(
            viewportWidth: 960,
            maxImageHeight: height,
            aspectRatio: shape.aspectRatio,
            density: density,
            tv: true,
            automaticWidth: 240,
          );
          expect(w / shape.aspectRatio, lessThanOrEqualTo(height + 0.001));
          expect(w.isFinite, isTrue);
          expect(w, greaterThan(0));
        }
      }
    }
  });
  test(
    'preferences persist notify each action and restore portable values',
    () async {
      SharedPreferences.setMockInitialValues({});
      final ui = UiSettings();
      await ui.load();
      var notifications = 0;
      ui.addListener(() => notifications++);
      final signature = ui.signature;
      await ui.setHomePosterShape(HomePosterShape.square);
      await ui.setHomeRecommendationLimit(15);
      await ui.setUiScale(110);
      expect(notifications, 3);
      expect(ui.signature, isNot(signature));
      final reloaded = UiSettings();
      await reloaded.load();
      expect(reloaded.homePosterShape, HomePosterShape.square);
      expect(reloaded.homeRecommendationLimit, 15);
      expect(reloaded.uiScalePercent, 110);
      final sync = SyncService(
        SupabaseClient('https://example.invalid', 'test'),
      );
      await sync.applySnapshotSettings({
        'ui_home_shape': 'landscape',
        'ui_scale': 90,
        'player_settings_tv_live_v1': '{"engine":"mpv"}',
      }, overwrite: true);
      await reloaded.load();
      expect(reloaded.homePosterShape, HomePosterShape.landscape);
      expect(reloaded.uiScalePercent, 90);
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          'player_settings_tv_live_v1',
        ),
        isFalse,
      );
    },
  );
  test(
    'reset publishes concrete defaults and leaves local player intact',
    () async {
      SharedPreferences.setMockInitialValues({'player_settings_v1': 'local'});
      final ui = UiSettings();
      await ui.load();
      await ui.setHomePosterShape(HomePosterShape.square);
      await ui.setUiScale(115);
      await ui.resetHomeLayout();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ui_home_shape'), 'portrait');
      expect(prefs.getString('ui_home_recent_shape'), 'portrait');
      expect(prefs.getInt('ui_home_recommendation_limit'), 10);
      expect(prefs.getInt('ui_home_recent_limit'), 50);
      expect(prefs.getInt('ui_scale'), 100);
      expect(prefs.getString('player_settings_v1'), 'local');
    },
  );
}
