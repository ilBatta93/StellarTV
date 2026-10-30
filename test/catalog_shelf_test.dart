import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/services/catalog_shelf.dart';

Channel row(int i, {ContentType type = ContentType.movie, String? name}) =>
    Channel(
      id: 'id-$i',
      name: name ?? 'Film $i',
      url: 'https://local/$i/stream',
      logo: '',
      group: 'A',
      type: type,
      addedAt: i,
    );

void main() {
  test('shelf keeps titles on disk and answers a prefix query', () async {
    final shelf = await CatalogShelf.fromChannels(
      [
        row(1, name: 'Il Padrino'),
        row(2, name: 'Inception'),
        row(3, name: 'Dark Matter', type: ContentType.series),
      ],
      hidden: const {},
      custom: const [],
      order: const {},
    );
    addTearDown(shelf.close);
    expect(shelf.length, greaterThanOrEqualTo(3));
    final padrino = shelf.searchSlots('padrino');
    expect(padrino, isNotEmpty);
    expect(shelf.readSlot(padrino.first).name, 'Il Padrino');
    expect(shelf.readId('id-2')?.url, contains('/2/'));
    final body = File(shelf.storagePath!).readAsStringSync();
    expect(body, contains('https://local/2/stream'));
  });

  test('a second section is appended without the first file', () async {
    final dir = Directory.systemTemp.createTempSync('stv_append_');
    final live = File('${dir.path}/live.ndjson');
    final movies = File('${dir.path}/movie.ndjson');
    writeSection(live, [row(1, name: 'Alfa Uno', type: ContentType.live)]);
    writeSection(movies, [row(2, name: 'Il Padrino')]);
    final shelf = CatalogShelf.empty();
    addTearDown(() async {
      shelf.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    const hidden = <String, List<String>>{};
    await shelf.appendSection(
      live.path,
      hidden: hidden,
      custom: const [],
      order: const {},
    );
    live.deleteSync();
    await shelf.appendSection(
      movies.path,
      hidden: hidden,
      custom: const [],
      order: const {},
    );
    expect(shelf.searchSlots('alfa'), isNotEmpty);
    final padrino = shelf.searchSlots('padrino');
    expect(padrino, isNotEmpty);
    expect(shelf.pathOfSlot(padrino.first), movies.path);
    expect(shelf.readSlot(padrino.first).url, contains('/2/'));
    expect(movies.readAsStringSync(), contains('https://local/2/stream'));
  });

  test('startup publishes the three sections from the saved index', () async {
    final dir = Directory.systemTemp.createTempSync('stv_index_');
    final live = File('${dir.path}/live.ndjson');
    final movies = File('${dir.path}/movie.ndjson');
    final series = File('${dir.path}/series.ndjson');
    writeSection(live, [row(1, name: 'Alfa Uno', type: ContentType.live)]);
    writeSection(movies, [row(2, name: 'Il Padrino')]);
    writeSection(series, [
      row(3, name: 'Dark Matter', type: ContentType.series),
    ]);
    const hidden = <String, List<String>>{};
    final built = CatalogShelf.empty();
    addTearDown(() async {
      built.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    for (final file in [live, movies, series]) {
      await built.appendSection(
        file.path,
        hidden: hidden,
        custom: const [],
        order: const {},
      );
    }
    final token = built.settingsToken;
    built.close();
    final restored = CatalogShelf.empty();
    addTearDown(restored.close);
    CatalogShelf.diskReads = 0;
    CatalogShelf.forbidDiskReads = true;
    try {
      expect(await restored.adoptIndex(live.path, token: token), isTrue);
      expect(await restored.adoptIndex(movies.path, token: token), isTrue);
      expect(await restored.adoptIndex(series.path, token: token), isTrue);
      expect(restored.plan(ContentType.live)?.channels, isNotEmpty);
      expect(restored.plan(ContentType.movie)?.channels, isNotEmpty);
      expect(restored.plan(ContentType.series)?.channels, isNotEmpty);
      expect(restored.searchSlots('padrino'), isNotEmpty);
      expect(CatalogShelf.diskReads, 0);
    } finally {
      CatalogShelf.forbidDiskReads = false;
    }
    final slot = restored.plan(ContentType.movie)!.channels.first;
    expect(restored.readSlot(slot).name, 'Il Padrino');
    expect(CatalogShelf.diskReads, 1);
  });

  test('kids warmup pairs facet keys without reading titles', () async {
    final shelf = await CatalogShelf.fromChannels(
      [row(1, name: 'Il Padrino'), row(2, name: 'Inception')],
      hidden: const {},
      custom: const [],
      order: const {},
    );
    addTearDown(shelf.close);
    final slot = shelf.plan(ContentType.movie)!.alphabetical.first;
    CatalogShelf.diskReads = 0;
    CatalogShelf.forbidDiskReads = true;
    try {
      final pairs = shelf.kidsIndexPairs([shelf.idAt(slot)], ['Il Padrino']);
      expect(pairs, hasLength(1));
      expect(pairs.single.key, shelf.facetKeyAt(slot));
      expect(pairs.single.title, 'Il Padrino');
      expect(CatalogShelf.diskReads, 0);
    } finally {
      CatalogShelf.forbidDiskReads = false;
    }
  });
}

void writeSection(File file, List<Channel> rows) {
  final buffer = StringBuffer()..writeln(jsonEncode({'stellar_catalog': 3}));
  for (final row in rows) {
    buffer.writeln(jsonEncode(row.toMap()));
  }
  buffer.writeln(jsonEncode({'end': rows.length}));
  file.writeAsStringSync(buffer.toString());
}
