import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/epg_archive.dart';
import 'package:stellar_tv/services/epg_prefix_index.dart';
import 'package:stellar_tv/services/epg_short.dart';

void main() {
  test('channel files answer one channel and a prefix without the other body', () async {
    final root = await Directory.systemTemp.createTemp('epg-index-');
    final now = DateTime.utc(2026, 10, 26, 18).millisecondsSinceEpoch;
    try {
      final header = writeEpgArchive('${root.path}/guide', {
        't': '2026-10-26T18:00:00.000Z',
        'd': false,
        'n': {'a': 'Alpha News', 'b': 'Beta'},
        'p': {
          'a': [
            [now, now + 3600000, 'Telegiornale', 'Sinossi del programma'],
          ],
          'b': [
            [now, now + 3600000, 'Film della sera', ''],
          ],
        },
      });
      final snapshot = EpgGuideSnapshot.fromHeader(header);
      expect(snapshot.programmeCount, 2);
      expect(snapshot.isEmpty, isFalse);
      expect(snapshot.programmesOf('a').single.title, 'Telegiornale');
      expect(snapshot.programmesOf('a').single.description, 'Sinossi del programma');
      final prefix = EpgPrefixIndex.fromJson(
        jsonDecode(File(snapshot.archive!.wordsPath).readAsStringSync()) as Map,
      );
      final alpha = snapshot.data.guideIds.indexOf('a');
      final beta = snapshot.data.guideIds.indexOf('b');
      expect(prefix.ordinals('teleg'), {alpha});
      expect(prefix.ordinals('alpha news'), {alpha});
      expect(prefix.ordinals('film sera'), {beta});
      expect(prefix.ordinals('teleg sera'), isEmpty);
      final slots = File('${root.path}/guide/slots.bin');
      final broken = slots.readAsBytesSync();
      final betaOffset = (header['off'] as List)[beta] as int;
      if (betaOffset >= 0 && betaOffset < broken.length) broken[betaOffset] = 0;
      slots.writeAsBytesSync(broken);
      snapshot.archive!.close();
      expect(snapshot.programmesOf('a').single.title, 'Telegiornale');
      snapshot.archive!.close();
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('short listings decode base64 titles and skip broken rows', () {
    final start = DateTime.utc(2026, 10, 26, 18);
    final raw = {
      'epg_listings': [
        {
          'title': base64Encode(utf8.encode('Notiziario')),
          'description': base64Encode(utf8.encode('Edizione')),
          'start_timestamp': '${start.millisecondsSinceEpoch ~/ 1000}',
          'stop_timestamp': '${start.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000}',
        },
        {'title': '===', 'start': 'not-a-date'},
      ],
    };
    final list = parseShortEpg(raw, '15');
    expect(list, hasLength(1));
    expect(list.single.title, 'Notiziario');
    expect(list.single.description, 'Edizione');
    expect(list.single.channelId, '15');
    expect(epgStreamId('live_15'), '15');
    expect(epgStreamId('movie_15'), isNull);
  });
}
