import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/services/kids_content_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kids-queue-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => dir.path);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await dir.delete(recursive: true);
  });

  Future<void> settled(KidsContentService service) async {
    for (var i = 0; i < 200 && service.queuedKeys.isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    // Let the last response finish before the client zone closes.
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  Map<String, Object> row(String key) => {
    'key': key,
    'is_kids': true,
    'genre_ids': [16],
    'certification': 'IT:T',
  };

  test('saved verdicts are read back from the device store', () async {
    File('${dir.path}/stellartv_kids_v3.json').writeAsStringSync(
      jsonEncode({
        'v': {'movie:noto': true},
        'g': {
          'movie:noto': [16],
        },
        'c': {'movie:noto': 'IT:T'},
      }),
    );
    final service = KidsContentService();
    addTearDown(service.dispose);
    await service.load();
    final item = Channel(
      id: '1',
      name: 'Noto',
      url: '',
      logo: '',
      group: 'Film',
      type: ContentType.movie,
    );
    expect(service.isKnown(item), isTrue);
  });

  test(
    'titles queued before the saved verdicts load are not re-sent',
    () async {
      File('${dir.path}/stellartv_kids_v3.json').writeAsStringSync(
        jsonEncode({
          'v': {'movie:noto': true},
          'g': {
            'movie:noto': [16],
          },
          'c': {'movie:noto': 'IT:T'},
        }),
      );
      final sent = <String>[];
      final service = KidsContentService();
      addTearDown(service.dispose);
      await http.runWithClient(
        () async {
          // The catalog warmup does not wait for load().
          service.requestIndexed([
            (key: 'movie:noto', title: 'Noto'),
            (key: 'movie:nuovo', title: 'Nuovo'),
          ]);
          await settled(service);
        },
        () => MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (request.url.path.endsWith('/kids-lookup')) {
            sent.addAll((body['keys'] as List).cast<String>());
            return http.Response(
              jsonEncode({
                'results': [row('movie:nuovo')],
              }),
              200,
            );
          }
          fail('unexpected ${request.url.path}');
        }),
      );
      expect(sent, ['movie:nuovo']);
    },
  );

  test('titles queued during a scan still use the bulk lookup', () async {
    final lookups = <List<String>>[];
    var checks = 0;
    final service = KidsContentService();
    addTearDown(service.dispose);
    await http.runWithClient(
      () async {
        service.requestIndexed([(key: 'movie:film', title: 'Film')]);
        await settled(service);
      },
      () => MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path.endsWith('/kids-check')) {
          checks++;
          return http.Response(jsonEncode({'results': []}), 200);
        }
        final keys = (body['keys'] as List).cast<String>();
        lookups.add(keys);
        // Another catalog type arrives while the first lookup is running.
        if (lookups.length == 1) {
          service.requestIndexed([(key: 'tv:serie', title: 'Serie')]);
        }
        return http.Response(
          jsonEncode({'results': keys.map(row).toList()}),
          200,
        );
      }),
    );
    expect(lookups, [
      ['movie:film'],
      ['tv:serie'],
    ]);
    expect(checks, 0);
    expect(service.queuedKeys, isEmpty);
  });

  // The catalog warmup queues a whole catalog in slices: every title must
  // still reach the bulk lookup, and known ones must stay out of it.
  test('a catalog queued in slices sends every unknown title', () async {
    File('${dir.path}/stellartv_kids_v3.json').writeAsStringSync(
      jsonEncode({
        'v': {'movie:t0': true},
        'g': {
          'movie:t0': [16],
        },
        'c': {'movie:t0': 'IT:T'},
      }),
    );
    final sent = <String>{};
    final service = KidsContentService();
    addTearDown(service.dispose);
    await service.load();
    await http.runWithClient(
      () async {
        await service.requestIndexedSliced([
          for (var i = 0; i < 3000; i++) (key: 'movie:t$i', title: 'T$i'),
        ]);
        await settled(service);
      },
      () => MockClient((request) async {
        if (!request.url.path.endsWith('/kids-lookup')) {
          return http.Response(jsonEncode({'results': []}), 200);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final keys = (body['keys'] as List).cast<String>();
        sent.addAll(keys);
        return http.Response(
          jsonEncode({'results': keys.map(row).toList()}),
          200,
        );
      }),
    );
    expect(sent, hasLength(2999));
    expect(sent, isNot(contains('movie:t0')));
    expect(service.queuedKeys, isEmpty);
  });

  // Titles the check cannot classify used to go back to the server at every
  // cold start: the cooldown lived only in memory.
  test('titles without a verdict wait a day across restarts', () async {
    final sent = <String>[];
    Future<void> session(void Function(KidsContentService) body) async {
      final service = KidsContentService();
      addTearDown(service.dispose);
      await http.runWithClient(
        () async {
          body(service);
          await settled(service);
          await service.saveNow();
        },
        () => MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (request.url.path.endsWith('/kids-lookup')) {
            sent.addAll((body['keys'] as List).cast<String>());
            return http.Response(jsonEncode({'results': []}), 200);
          }
          final items = (body['items'] as List).cast<Map>();
          sent.addAll(items.map((i) => 'check:${i['title']}'));
          return http.Response(
            jsonEncode({
              'results': [
                for (final i in items)
                  {
                    'title': i['title'],
                    'type': i['type'],
                    'is_kids': null,
                    'genre_ids': null,
                    'certification': null,
                  },
              ],
            }),
            200,
          );
        }),
      );
    }

    await session(
      (s) => s.requestIndexed([(key: 'movie:ignoto', title: 'Ignoto')]),
    );
    expect(sent, ['movie:ignoto', 'check:Ignoto']);

    sent.clear();
    await session(
      (s) => s.requestIndexed([(key: 'movie:ignoto', title: 'Ignoto')]),
    );
    expect(sent, isEmpty);

    // After a day the title is asked again.
    final file = File('${dir.path}/stellartv_kids_v3.json');
    final store = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final dayAgo = DateTime.now()
        .subtract(KidsContentService.unansweredFor)
        .millisecondsSinceEpoch;
    store['u'] = {'movie:ignoto': dayAgo};
    file.writeAsStringSync(jsonEncode(store));
    sent.clear();
    await session(
      (s) => s.requestIndexed([(key: 'movie:ignoto', title: 'Ignoto')]),
    );
    expect(sent, ['movie:ignoto', 'check:Ignoto']);
  });
}
