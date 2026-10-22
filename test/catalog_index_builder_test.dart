import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/services/catalog_index_builder.dart';

Channel ep(String id, String name, String key) => Channel(
  id: id,
  name: name,
  url: 'http://x/$id',
  logo: '',
  group: 'Serie',
  type: ContentType.series,
  seriesKey: key,
  seriesName: 'Dark',
);

void main() {
  test('title keys match the Home lookup normalization', () {
    expect(catalogTitleKey('IT: Inception (2010) [4K]'), 'inception');
    expect(catalogTitleKey('Il Padrino 1972 FHD'), 'il padrino');
  });

  test('index groups series and points to movies in background isolate', () async {
    final movies = ['IT: Inception (2010)', 'Matrix'];
    final series = [ep('1', 'Dark S01E01', 'dark'), ep('2', 'Dark S01E02', 'dark')];
    final data = await Isolate.run(
      () => buildCatalogIndex(movies, series, const []),
    );
    expect(data.seriesCatalog, hasLength(1));
    expect(data.seriesCatalog.single.isSeriesFolder, isTrue);
    final inception = data.titles['inception']!.single;
    expect(CatalogIndexData.kindOf(inception), 0);
    expect(CatalogIndexData.indexOf(inception), 0);
    final dark = data.titles['dark']!.single;
    expect(CatalogIndexData.kindOf(dark), 1);
    expect(CatalogIndexData.indexOf(dark), 0);
  });

  test('already grouped series are kept as they are', () {
    final folder = ep('dark', 'Dark', 'dark').copyWith(isSeriesFolder: true);
    final data = buildCatalogIndex(
      const [],
      [folder],
      const [],
      alreadyGrouped: (true, true),
    );
    expect(data.seriesCatalog.single.id, 'dark');
  });

  test('50k titles index under 3 s off the UI thread', () async {
    final names = [for (var i = 0; i < 50000; i++) 'IT: Film $i (2020) [HD]'];
    final sw = Stopwatch()..start();
    final data = await Isolate.run(
      () => buildCatalogIndex(names, const [], const []),
    );
    // Numbers like 1999 read as years and merge, as in the real Home lookup.
    expect(data.titles.length, greaterThan(49000));
    expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
  });
}
