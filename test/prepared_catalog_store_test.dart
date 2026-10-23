import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/services/catalog_preparation.dart';
import 'package:stellar_tv/services/prepared_catalog_store.dart';

Channel item(int i, {String group = 'A', String? name}) => Channel(
  id: '$i',
  name: name ?? 'Title $i',
  url: 'local',
  logo: '',
  group: group,
  type: ContentType.movie,
  addedAt: i,
);

Future<String> sig(List<Channel> rows, {Set<String> hidden = const {}}) =>
    PreparedCatalogStore.signature(
      snapshot: rows,
      type: ContentType.movie,
      hidden: hidden,
      custom: const [],
      order: const [],
      yieldWork: CatalogYield(() async => true),
    );

void main() {
  test('persisted genre counts roundtrip without rescanning title metadata', () {
    const prepared = PreparedCatalog([], [], [], [], []);
    final data = PreparedCatalogStore.encode('scope', prepared,
        genreCounts: {16: 23, 10765: 5});
    expect(PreparedCatalogStore.genreCounts(Map<String, dynamic>.from(data)),
        {16: 23, 10765: 5});
    expect(PreparedCatalogStore.genreCounts({'genreCounts': {'16': -1}}), isNull);
    expect(PreparedCatalogStore.genreCounts({}), isNull);
  });
  final y = CatalogYield(() async => true);
  test(
    'unchanged playlist restores the same structure without re-preparing',
    () async {
      final rows = [item(1), item(2, group: 'B'), item(3, group: 'B')];
      final prepared = await prepareCatalog(
        snapshot: rows,
        type: ContentType.movie,
        hidden: {},
        custom: [],
        order: [],
        yieldWork: y,
      );
      final s = await sig(rows);
      final data = PreparedCatalogStore.encode(s, prepared);
      final restored = await PreparedCatalogStore.restore(
        Map<String, dynamic>.from(data),
        s,
        rows,
        ContentType.movie,
        y,
      );
      expect(restored, isNotNull);
      expect(
        restored!.groups.map((g) => g.label),
        prepared.groups.map((g) => g.label),
      );
      expect(
        restored.recent.map((e) => e.primary.id),
        prepared.recent.map((e) => e.primary.id),
      );
      expect(
        restored.all.map((e) => e.primary.id),
        prepared.all.map((e) => e.primary.id),
      );
    },
  );
  test(
    'a changed playlist or hidden category invalidates the saved structure',
    () async {
      final rows = [item(1), item(2)];
      final s = await sig(rows);
      expect(await sig([...rows, item(3)]), isNot(s));
      expect(await sig([item(1), item(2, name: 'Renamed')]), isNot(s));
      expect(await sig(rows, hidden: {'A'}), isNot(s));
      final prepared = await prepareCatalog(
        snapshot: rows,
        type: ContentType.movie,
        hidden: {},
        custom: [],
        order: [],
        yieldWork: y,
      );
      final data = Map<String, dynamic>.from(
        PreparedCatalogStore.encode(s, prepared),
      );
      expect(
        await PreparedCatalogStore.restore(
          data,
          'other',
          rows,
          ContentType.movie,
          y,
        ),
        isNull,
      );
      expect(
        await PreparedCatalogStore.restore(
          data,
          s,
          [item(1)],
          ContentType.movie,
          y,
        ),
        isNull,
      );
    },
  );
}
