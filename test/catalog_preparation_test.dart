import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/services/catalog_builder.dart';
import 'package:stellar_tv/services/catalog_preparation.dart';

Channel item(int i, {String? name, String group = 'A'}) => Channel(
  id: '$i', name: name ?? 'Title $i', url: 'local', logo: '', group: group,
  type: ContentType.movie, addedAt: i);

void main() {
  test('progressive grouping preserves primary identifiers and first category ownership', () async {
    final rows = [item(1, name: 'Same [4K]'), item(2, name: 'Same (1080p)', group: 'B'), item(3, group: 'B')];
    final result = await prepareCatalog(snapshot: rows, type: ContentType.movie,
      hidden: {}, custom: [], order: [], yieldWork: CatalogYield(() async => true));
    final expected = CatalogBuilder.groupsOf(rows, ['A', 'B']);
    expect(result.groups.map((g) => g.label), expected.map((g) => g.label));
    expect(result.groups.expand((g) => g.entries).map((e) => e.primary.id), ['1', '3']);
    expect(result.recent.first.primary.id, '3');
  });
  test('preparation runs off the calling isolate', () async {
    var ticks = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 1), (_) => ticks++);
    try {
      final rows = List.generate(8000, (i) => item(i));
      final result = await prepareCatalog(
        snapshot: rows,
        type: ContentType.movie,
        hidden: {},
        custom: [],
        order: [],
        yieldWork: CatalogYield(() async => true),
      );
      expect(result.catalog, hasLength(8000));
      expect(ticks, greaterThan(0));
    } finally {
      timer.cancel();
    }
  });
  test('hidden categories stay excluded', () async {
    final result = await prepareCatalog(snapshot: [item(1), item(2, group: 'Hidden')],
      type: ContentType.movie, hidden: {'Hidden'}, custom: [], order: [],
      yieldWork: CatalogYield(() async => true));
    expect(result.all.map((e) => e.primary.id), ['1']);
    expect(result.recent.map((e) => e.primary.id), ['1']);
  });
}