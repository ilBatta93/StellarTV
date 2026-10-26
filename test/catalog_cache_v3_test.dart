import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/services/catalog_cache_service.dart';
import 'package:stellar_tv/services/playback_work_policy.dart';

Channel item(int i, ContentType type) => Channel(
  id: '${type.name}_$i',
  name: 'Titolo $i',
  url: 'http://example.invalid/$i',
  logo: '',
  group: 'Gruppo ${i % 7}',
  type: type,
);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('stv_cache'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('v3 round trip keeps every title in order', () async {
    final path = '${dir.path}/movie.ndjson';
    final rows = [for (var i = 0; i < 5000; i++) item(i, ContentType.movie)];
    expect(await writeCatalogFile(path, rows), true);
    final back = await readCatalogFileV3(path);
    expect(back, hasLength(5000));
    expect(back!.first.id, 'movie_0');
    expect(back.last.id, 'movie_4999');
    expect(back[42].group, 'Gruppo 0');
    expect(File('$path.tmp').existsSync(), false);
  });

  test('incomplete v3 copy falls back to the previous v2 copy', () async {
    final v3 = '${dir.path}/live.ndjson';
    final v2 = '${dir.path}/live.json';
    File(v2).writeAsStringSync(jsonEncode([item(1, ContentType.live).toMap()]));
    expect(
      await writeCatalogFile(v3, [
        item(1, ContentType.live),
        item(2, ContentType.live),
      ]),
      true,
    );
    // Simulate a save cut before the end marker.
    final lines = File(v3).readAsLinesSync();
    File(v3).writeAsStringSync('${lines.take(lines.length - 1).join('\n')}\n');
    expect(await readCatalogFileV3(v3), isNull);
    final all = await readCatalogFiles([(v3, v2)], '${dir.path}/none.json');
    expect(all.map((c) => c.id), ['live_1']);
  });

  test(
    'sections are read independently and legacy only when none exist',
    () async {
      final legacy = '${dir.path}/v1.json';
      File(legacy)
          .writeAsStringSync(jsonEncode([item(9, ContentType.series).toMap()]));
      final empty = await readCatalogFiles([
        ('${dir.path}/a.ndjson', '${dir.path}/a.json'),
      ], legacy);
      expect(empty.map((c) => c.id), ['series_9']);
      final v3 = '${dir.path}/b.ndjson';
      await writeCatalogFile(v3, [item(3, ContentType.movie)]);
      final mixed = await readCatalogFiles([
        (v3, '${dir.path}/b.json'),
        ('${dir.path}/c.ndjson', '${dir.path}/c.json'),
      ], legacy);
      expect(mixed.map((c) => c.id), ['movie_3']);
    },
  );

  test('a refused replace leaves the previous copy and no temp file', () async {
    final path = '${dir.path}/movie.ndjson';
    expect(await writeCatalogFile(path, [item(1, ContentType.movie)]), true);
    final refused = await writeCatalogFile(
      path,
      [item(2, ContentType.movie)],
      stillAllowed: () {
        final temporary = File('$path.tmp');
        return !temporary.existsSync() || temporary.lengthSync() == 0;
      },
    );
    expect(refused, false);
    final back = await readCatalogFileV3(path);
    expect(back!.single.id, 'movie_1');
    expect(File('$path.tmp').existsSync(), false);
  });

  test('open session does not encode a catalog section', () async {
    final session = Object();
    PlaybackWorkPolicy.instance.update(session, cloudBlocked: false);
    try {
      final saved = await CatalogCacheService().writeSection(
        'account',
        ContentType.movie,
        [item(1, ContentType.movie)],
      );
      expect(saved, false);
    } finally {
      PlaybackWorkPolicy.instance.remove(session);
    }
  });

  test('empty section is saved and read as empty, not missing', () async {
    final path = '${dir.path}/e.ndjson';
    expect(await writeCatalogFile(path, const []), true);
    expect(await readCatalogFileV3(path), isEmpty);
  });
}
