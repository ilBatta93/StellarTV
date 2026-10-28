import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/services/catalog_publication.dart';

Channel item(int n, ContentType type) => Channel(
  id: '$n',
  name: 'Item $n',
  url: 'local:$n',
  logo: '',
  group: 'Test',
  type: type,
);
void main() {
  test(
    '100000-entry replacement yields to remote events and preserves sibling ids and input',
    () async {
      final current = [
        for (var i = 0; i < 100000; i++)
          item(i, i.isEven ? ContentType.live : ContentType.movie),
      ];
      final replacement = [item(200001, ContentType.movie)];
      var events = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 1),
        (_) => events++,
      );
      final output = await replaceCatalogSection(
        current: current,
        replacement: replacement,
        type: ContentType.movie,
        stillCurrent: () => true,
      );
      timer.cancel();
      expect(output, hasLength(50001));
      expect(output?.first.id, '0');
      expect(output?.last.id, '200001');
      expect(current, hasLength(100000));
      expect(events, greaterThan(0));
    },
  );
  test(
    'changed account/playback discards publication rather than altering input',
    () async {
      final current = [
        for (var i = 0; i < 1000; i++) item(i, ContentType.live),
      ];
      var valid = true;
      final result = replaceCatalogSection(
        current: current,
        replacement: [],
        type: ContentType.live,
        stillCurrent: () => valid,
      );
      valid = false;
      expect(await result, isNull);
      expect(current, hasLength(1000));
    },
  );
  test(
    'strict evidence filter never publishes unapproved entries, bounded evidence batches',
    () async {
      final current = [
        for (var i = 0; i < 1000; i++) item(i, ContentType.movie),
      ];
      var checked = 0;
      var biggest = 0;
      final result = await filterCatalogForPublication(
        channels: current,
        allowed: (c) => int.parse(c.id).isEven,
        stillCurrent: () => true,
        requestEvidence: (batch) {
          checked += batch.length;
          if (batch.length > biggest) biggest = batch.length;
        },
      );
      expect(result, hasLength(500));
      expect(result?.every((c) => int.parse(c.id).isEven), true);
      expect(checked, 1000);
      expect(biggest, lessThanOrEqualTo(128));
    },
  );
  test(
    'changed evidence or profile during filtering discards the old result',
    () async {
      var valid = true;
      final result = filterCatalogForPublication(
        channels: [for (var i = 0; i < 1000; i++) item(i, ContentType.movie)],
        allowed: (_) => true,
        stillCurrent: () => valid,
      );
      valid = false;
      expect(await result, isNull);
    },
  );
}
