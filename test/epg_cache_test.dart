import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/epg_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'guide cache persists in support storage and rejects other sources',
    () async {
      final dir = await Directory.systemTemp.createTemp('epg-persistent-test');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => dir.path);
      final sources = ['https://example.invalid/a'];
      final changed = ['https://example.invalid/b'];
      final at = DateTime.utc(2026, 10, 23, 14);
      try {
        await File(
          '${dir.path}/stellartv_epg_v2_${EpgService.sourceKey(sources)}.json',
        ).writeAsString(
          jsonEncode({
            'p': {
              'c': [
                [
                  at.millisecondsSinceEpoch,
                  at.add(const Duration(hours: 1)).millisecondsSinceEpoch,
                  'Program',
                  '',
                ],
              ],
            },
            'n': {'c': 'Channel'},
            't': at.toIso8601String(),
          }),
        );
        final restored = await EpgService().loadCache(sources);
        expect(restored.programmeCount, 1);
        expect(restored.fetchedAt, at);
        expect((await EpgService().loadCache(changed)).isEmpty, true);
        expect((await EpgService().loadCache(sources)).programmeCount, 1);
        expect(
          EpgService.sourceKey(sources),
          isNot(EpgService.sourceKey(changed)),
        );
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await dir.delete(recursive: true);
      }
    },
  );
}
