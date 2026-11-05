import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/catalog_start_category.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/services/catalog_sort.dart';
import 'package:stellar_tv/services/catalog_view_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sort orders are remembered per tab', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await CatalogViewMemory.sort(ContentType.movie), isNull);
    await CatalogViewMemory.saveSort(ContentType.movie, CatalogSort.rating);
    await CatalogViewMemory.saveSort(ContentType.live, CatalogSort.nameAsc);
    expect(await CatalogViewMemory.sort(ContentType.movie), CatalogSort.rating);
    expect(await CatalogViewMemory.sort(ContentType.live), CatalogSort.nameAsc);
    expect(await CatalogViewMemory.sort(ContentType.series), isNull);
  });

  test('an unknown saved sort falls back to the default', () async {
    SharedPreferences.setMockInitialValues({'catalog_sort_movie': 'gone'});
    expect(await CatalogViewMemory.sort(ContentType.movie), isNull);
  });

  test('the Diretta category tells "never picked" from "Tutti"', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await CatalogViewMemory.liveCategory(), (saved: false, label: null));
    await CatalogViewMemory.saveLiveCategory(null);
    expect(await CatalogViewMemory.liveCategory(), (saved: true, label: null));
    await CatalogViewMemory.saveLiveCategory('Sport');
    expect(await CatalogViewMemory.liveCategory(), (
      saved: true,
      label: 'Sport',
    ));
  });

  test('each tab keeps its own opening category, on the device only', () async {
    SharedPreferences.setMockInitialValues({});
    // Defaults: Diretta where it was left, Film and Serie TV on the newest.
    expect(
      await CatalogViewMemory.startCategory(ContentType.live),
      const CatalogStartCategory(CatalogStartKind.last),
    );
    expect(
      await CatalogViewMemory.startCategory(ContentType.movie),
      const CatalogStartCategory(CatalogStartKind.newest),
    );
    await CatalogViewMemory.saveStartCategory(
      ContentType.series,
      const CatalogStartCategory(CatalogStartKind.group, 'Animazione'),
    );
    await CatalogViewMemory.saveStartCategory(
      ContentType.live,
      const CatalogStartCategory(CatalogStartKind.watched),
    );
    expect(
      await CatalogViewMemory.startCategory(ContentType.series),
      const CatalogStartCategory(CatalogStartKind.group, 'Animazione'),
    );
    expect(
      await CatalogViewMemory.startCategory(ContentType.live),
      const CatalogStartCategory(CatalogStartKind.watched),
    );
    expect(
      await CatalogViewMemory.startCategory(ContentType.movie),
      const CatalogStartCategory(CatalogStartKind.newest),
    );
  });

  test('broken or unsuitable opening categories fall back', () {
    for (final raw in [null, 7, '', 'gone', 'group:', 'group']) {
      expect(
        CatalogStartCategory.parse(raw, ContentType.movie),
        const CatalogStartCategory(CatalogStartKind.newest),
        reason: '$raw',
      );
    }
    // Diretta has no "latest additions" view.
    expect(
      CatalogStartCategory.parse('newest', ContentType.live),
      const CatalogStartCategory(CatalogStartKind.last),
    );
    expect(
      CatalogStartCategory.kindsFor(ContentType.live),
      isNot(contains(CatalogStartKind.newest)),
    );
  });

  test('the last Film and Serie TV category is remembered per tab', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await CatalogViewMemory.lastCategory(ContentType.movie), isNull);
    await CatalogViewMemory.saveLastCategory(ContentType.movie, 'Commedia');
    expect(await CatalogViewMemory.lastCategory(ContentType.movie), 'Commedia');
    expect(await CatalogViewMemory.lastCategory(ContentType.series), isNull);
    await CatalogViewMemory.saveLastCategory(ContentType.movie, null);
    expect(await CatalogViewMemory.lastCategory(ContentType.movie), isNull);
    // Diretta keeps its existing memory.
    await CatalogViewMemory.saveLastCategory(ContentType.live, 'Sport');
    expect(await CatalogViewMemory.liveCategory(), (
      saved: true,
      label: 'Sport',
    ));
  });
}
