import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
}
