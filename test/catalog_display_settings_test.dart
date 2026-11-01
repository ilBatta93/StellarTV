import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/providers/ui_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Film and Serie TV keep their own layout over the common one', () async {
    SharedPreferences.setMockInitialValues({'ui_catalog_view': 'compact'});
    final ui = UiSettings();
    await ui.load();
    expect(ui.viewModeFor(ContentType.movie), CatalogViewMode.compact);
    expect(ui.viewModeFor(ContentType.series), CatalogViewMode.compact);

    await ui.setCatalogViewMode(CatalogViewMode.list, type: ContentType.movie);
    await ui.setCatalogViewMode(
      CatalogViewMode.spotlight,
      type: ContentType.anime,
    );
    final reloaded = UiSettings();
    await reloaded.load();
    expect(reloaded.viewModeFor(ContentType.movie), CatalogViewMode.list);
    expect(reloaded.viewModeFor(ContentType.series), CatalogViewMode.spotlight);
    expect(reloaded.viewModeFor(ContentType.live), CatalogViewMode.compact);

    // The common choice clears both, also for the cloud copy.
    await reloaded.setCatalogViewMode(CatalogViewMode.grid);
    expect(reloaded.viewModeFor(ContentType.movie), CatalogViewMode.grid);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ui_catalog_view_movie'), 'common');
    final again = UiSettings();
    await again.load();
    expect(again.viewModeFor(ContentType.series), CatalogViewMode.grid);
  });

  test('heart and Diretta options persist and reset to defaults', () async {
    SharedPreferences.setMockInitialValues({});
    final ui = UiSettings();
    await ui.load();
    expect(ui.favoriteHeart, isTrue);
    expect(ui.liveNumbers, isFalse);
    expect(ui.livePreview, isTrue);
    final signature = ui.signature;
    await ui.setFavoriteHeart(false);
    await ui.setLiveNumbers(true);
    await ui.setLivePreview(false);
    expect(ui.signature, isNot(signature));
    final reloaded = UiSettings();
    await reloaded.load();
    expect(reloaded.favoriteHeart, isFalse);
    expect(reloaded.liveNumbers, isTrue);
    expect(reloaded.livePreview, isFalse);
    await reloaded.resetAppearance();
    expect(reloaded.favoriteHeart, isTrue);
    expect(reloaded.liveNumbers, isFalse);
    expect(reloaded.livePreview, isTrue);
  });
}
