import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/services/catalog_builder.dart';
import 'package:stellar_tv/services/catalog_sort.dart';
import 'package:stellar_tv/services/title_matching.dart';

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

List<String> ids(Iterable<Channel> list) => list.map((c) => c.id).toList();

List<CatalogEntry> entriesOf(List<Channel> source) => [
  for (final c in source) CatalogEntry(primary: c, variants: [c]),
];

void main() {
  final source = [
    item('old', 'A', 19990501, 900),
    item('new', 'B', 20240101, 100),
    item('missing', 'Unknown', 0, 0),
  ];
  double? rating(Channel c) => {'old': 5.0, 'new': 9.0}[c.id];

  test(
    'background sorting matches the synchronous order for every sort',
    () async {
      for (final order in CatalogSort.values) {
        final before = ids(source);
        final result = await sortCatalogBackground(entriesOf(source), order, {
          'old': 5,
          'new': 9,
        });
        final sync = sortCatalog(source, order, (c) => c, ratingOf: rating);
        expect(
          ids(result.map((e) => e.primary)),
          ids(sync),
          reason: 'isolate differs: $order',
        );
        expect(ids(source), before, reason: 'source mutated');
      }
    },
  );

  test('release sorts use the release date and place unknown last', () {
    expect(ids(sortCatalog(source, CatalogSort.releaseDesc, (c) => c)), [
      'new',
      'old',
      'missing',
    ]);
    expect(ids(sortCatalog(source, CatalogSort.releaseAsc, (c) => c)), [
      'old',
      'new',
      'missing',
    ]);
  });

  test('rating sort keeps the rating snapshot', () {
    expect(
      ids(sortCatalog(source, CatalogSort.rating, (c) => c, ratingOf: rating)),
      ['new', 'old', 'missing'],
    );
  });

  test(
    '100000 entries sort off the UI thread without mutating the source',
    () async {
      final large = [
        for (var i = 0; i < 100000; i++)
          CatalogEntry(
            primary: item('$i', 'Title $i', 0, i),
            variants: const [],
          ),
      ];
      final result = await sortCatalogBackground(
        large,
        CatalogSort.dateDesc,
        {},
      );
      expect(result.length, 100000);
      expect(result.first.primary.id, '99999');
      expect(result.last.primary.id, '0');
      expect(large.first.primary.id, '0');
    },
  );

  test('rating indices and saved order', () {
    expect(indicesByRating(const [5, 9, 0], const ['b', 'a', 'c']), [1, 0, 2]);
    final applied = applyCatalogOrder(entriesOf(source), const [
      'new',
      'missing',
      'old',
      'ghost',
    ]);
    expect(ids(applied.map((e) => e.primary)), ['new', 'missing', 'old']);
    // Shelf entries pass their id from the index: no title is read.
    final reads = <String>[];
    final byIndex = applyCatalogOrder(
      entriesOf(source),
      const ['old', 'new'],
      idOf: (e) {
        reads.add(e.primary.id);
        return e.primary.id;
      },
    );
    expect(ids(byIndex.map((e) => e.primary)), ['old', 'new', 'missing']);
    expect(reads, hasLength(source.length));
  });

  test(
    'known ratings prefer IMDb, then the stored vote, unknown last',
    () async {
      final aKey = parseTitle('A').key(ContentType.movie.name);
      final bKey = parseTitle('B').key(ContentType.movie.name);
      final byRating = await sortCatalogByKnownRatings(
        entriesOf(source),
        {aKey: 4},
        {bKey: 'movie:2'},
        {'movie:2': 9},
      );
      expect(ids(byRating.map((e) => e.primary)), ['new', 'old', 'missing']);
    },
  );
}
