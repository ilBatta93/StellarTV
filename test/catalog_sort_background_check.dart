import '../lib/models/channel.dart';
import '../lib/models/content_type.dart';
import '../lib/services/catalog_builder.dart';
import '../lib/services/catalog_sort.dart';

void require(bool ok, String message) {
  if (!ok) throw StateError(message);
}

Channel item(String id, String name, int release, int added) => Channel(
  id: id,
  name: name,
  url: '',
  logo: '',
  group: '',
  type: ContentType.movie,
  releaseDate: release,
  addedAt: added,
);
Future<void> main() async {
  final source = [
    item('old', 'A', 19990501, 900),
    item('new', 'B', 20240101, 100),
    item('missing', 'Unknown', 0, 0),
  ];
  List<String> ids(List<Channel> list) => list.map((c) => c.id).toList();
  for (final order in CatalogSort.values) {
    final entries = [
      for (final c in source) CatalogEntry(primary: c, variants: [c]),
    ];
    final before = ids(source).join(',');
    final result = await sortCatalogBackground(entries, order, {
      'old': 5,
      'new': 9,
    });
    final sync = sortCatalog(
      source,
      order,
      (c) => c,
      ratingOf: (c) => {'old': 5.0, 'new': 9.0}[c.id],
    );
    require(
      ids(result.map((e) => e.primary).toList()).join(',') ==
          ids(sync).join(','),
      'isolate differs: $order',
    );
    require(ids(source).join(',') == before, 'source mutated');
  }
  require(
    ids(sortCatalog(source, CatalogSort.releaseDesc, (c) => c)).join(',') ==
        'new,old,missing',
    'release newest uses release, not addition',
  );
  require(
    ids(sortCatalog(source, CatalogSort.releaseAsc, (c) => c)).join(',') ==
        'old,new,missing',
    'release oldest places unknown last',
  );
  require(
    ids(
          sortCatalog(
            source,
            CatalogSort.rating,
            (c) => c,
            ratingOf: (c) => {'old': 5.0, 'new': 9.0}[c.id],
          ),
        ).join(',') ==
        'new,old,missing',
    'rating snapshot lost',
  );
  final large = [
    for (var i = 0; i < 100000; i++)
      CatalogEntry(primary: item('$i', 'Title $i', 0, i), variants: const []),
  ];
  final result = await sortCatalogBackground(large, CatalogSort.dateDesc, {});
  require(
    result.length == 100000 &&
        result.first.primary.id == '99999' &&
        result.last.primary.id == '0',
    'large ordering wrong',
  );
  require(large.first.primary.id == '0', 'large source mutated');
  print(
    'PASS: eight isolate orders, release dates, rating snapshots and 100000 entries',
  );
}
