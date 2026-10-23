import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/services/catalog_index_builder.dart';
import 'package:stellar_tv/services/title_category_index.dart';

Channel title(String id, String name, String group, ContentType type) =>
    Channel(id: id, name: name, group: group, type: type, url: '', logo: '');

void main() {
  test('same normalized title lists all categories only once', () async {
    final a = title('a', 'IT: Dark [HD]', 'Netflix', ContentType.series);
    final b = title('b', 'Dark [4K]', 'Novità', ContentType.series);
    final index = await Isolate.run(
      () => buildTitleCategoryIndex([
        a,
        b,
        title('c', 'Dark', 'Netflix', ContentType.series),
      ]),
    );
    expect(index[catalogEntryKey(a)], ['Netflix', 'Novità']);
  });
  test('movie and series categories remain separate', () {
    final movie = title('m', 'Dark', 'Cinema', ContentType.movie);
    final series = title('s', 'Dark', 'Serie', ContentType.series);
    final index = buildTitleCategoryIndex([movie, series]);
    expect(index[catalogEntryKey(movie)], ['Cinema']);
    expect(index[catalogEntryKey(series)], ['Serie']);
  });
  test('new snapshot replaces previous categories', () {
    final a = title('a', 'Dark', 'Vecchia', ContentType.series);
    final b = title('a', 'Dark', 'Nuova', ContentType.series);
    expect(buildTitleCategoryIndex([a])[catalogEntryKey(a)], ['Vecchia']);
    expect(buildTitleCategoryIndex([b])[catalogEntryKey(b)], ['Nuova']);
  });
}
