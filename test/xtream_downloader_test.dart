import 'dart:convert';
import 'dart:io' hide ContentType;
import 'dart:io' as io show ContentType;

import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/services/xtream_downloader.dart';

void main() {
  HttpServer? server;
  Future<String> start() async {
    if (server != null) return 'http://127.0.0.1:${server!.port}';
    final s = server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    s.listen((request) async {
      final action = request.uri.queryParameters['action'];
      final res = request.response..headers.contentType = io.ContentType.json;
      switch (action) {
        case 'get_live_categories':
          res.write('[{"category_id":"1","category_name":"Sport"}]');
        case 'get_live_streams':
          // Big list sent in many small chunks, with escaped quotes/braces.
          res.write('\uFEFF[');
          for (var i = 0; i < 5000; i++) {
            if (i > 0) res.write(',');
            res.write(
              jsonEncode({
                'stream_id': i,
                'name': 'Canale "$i" {HD} [IT]',
                'category_id': '1',
                'stream_icon': '',
              }),
            );
            if (i % 200 == 0) await res.flush();
          }
          res.write(']');
        case 'get_vod_streams':
          // Truncated payload: the last element is incomplete.
          res.write(
            '[{"stream_id":1,"name":"A"},{"stream_id":2,"name":"B"},'
            '{"stream_id":3,"na',
          );
        case 'get_series':
          // Some panels answer with an object keyed by id.
          res.write(
            '{"7":{"series_id":7,"name":"Serie"},'
            '"8":{"series_id":8,"name":"Altra"}}',
          );
        default:
          res.write('[]');
      }
      await res.close();
    });
    return 'http://127.0.0.1:${s.port}';
  }

  test('Streams a big list in background and reports progress', () async {
    final progress = <CatalogProgress>[];
    final channels = await downloadXtreamSection(
      base: await start(),
      username: 'u',
      password: 'p',
      type: ContentType.live,
      onProgress: progress.add,
    );
    expect(channels, hasLength(5000));
    expect(channels.first.group, 'Sport');
    expect(channels[42].name, 'Canale "42" {HD} [IT]');
    expect(progress.last.items, 5000);
  });

  test('Keeps complete items of a truncated list', () async {
    final channels = await downloadXtreamSection(
      base: await start(),
      username: 'u',
      password: 'p',
      type: ContentType.movie,
    );
    expect(channels.map((c) => c.name), ['A', 'B']);
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('Accepts object-shaped responses', () async {
    final channels = await downloadXtreamSection(
      base: await start(),
      username: 'u',
      password: 'p',
      type: ContentType.series,
    );
    expect(channels.map((c) => c.id), ['series_7', 'series_8']);
  });

  test('Unreachable server fails with a readable message', () async {
    await expectLater(
      downloadXtreamSection(
        base: 'http://127.0.0.1:1',
        username: 'u',
        password: 'p',
        type: ContentType.live,
      ),
      throwsA(
        isA<XtreamDownloadException>().having(
          (e) => e.message,
          'message',
          contains('server della playlist'),
        ),
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 40)));
}
