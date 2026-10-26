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
}
