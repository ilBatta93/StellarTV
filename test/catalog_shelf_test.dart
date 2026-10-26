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
    writeSection(live, [
      row(1, name: 'Alfa Uno', type: ContentType.live),
    ]);
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
}

void writeSection(File file, List<Channel> rows) {
  final buffer = StringBuffer()
    ..writeln(jsonEncode({'stellar_catalog': 3}));
  for (final row in rows) {
    buffer.writeln(jsonEncode(row.toMap()));
  }
  buffer.writeln(jsonEncode({'end': rows.length}));
  file.writeAsStringSync(buffer.toString());
}
