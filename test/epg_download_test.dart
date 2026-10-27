import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/providers/epg_provider.dart';
import '../lib/services/epg_archive.dart';
import '../lib/services/epg_downloader.dart';

String fixture() {
  final now = DateTime.now().toUtc();
  String time(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}00 +0000';
  return '''<?xml version="1.0"?><tv><channel id='c'><display-name>C &amp; &#233;</display-name></channel><programme channel='c' start='${time(now.subtract(const Duration(hours: 3)))}' stop='${time(now.subtract(const Duration(hours: 2)))}'><title><![CDATA[Past <title>]]></title><desc>Safe</desc></programme><programme start='${time(now)}' stop='${time(now.add(const Duration(hours: 1)))}' channel='c'><title>Current</title></programme></tv>''';
}

void main() {
  test(
    'XMLTV accepts colon offsets and rejects invalid dates and trailing garbage',
    () {
      expect(
        parseXmltvTime('20261023021900 +02:00'),
        DateTime.utc(2026, 10, 23, 0, 19).millisecondsSinceEpoch,
      );
      expect(
        parseXmltvTime('20261023021900 +0200'),
        parseXmltvTime('20261023021900 +02:00'),
      );
      expect(parseXmltvTime('20260231021900 +0200'), isNull);
      expect(parseXmltvTime('20261023021900 +0200garbage'), isNull);
    },
  );
  test(
    'incremental XML keeps past six hours, quote variants, CDATA and entities',
    () async {
      final bytes = utf8.encode(fixture());
      final parsed = await parseXmltvStream(
        Stream.fromIterable([
          for (var i = 0; i < bytes.length; i += 7)
            bytes.sublist(i, (i + 7).clamp(0, bytes.length)),
        ]),
        DateTime.now(),
      );
      expect((parsed['p'] as Map)['c'], hasLength(2));
      expect(((parsed['p'] as Map)['c'] as List).first[2], 'Past <title>');
      expect((parsed['n'] as Map)['c'], 'C & é');
    },
  );
  test('a guide past the programme cap stays partial instead of failing', () async {
    final parsed = await parseXmltvStream(
      Stream.value(utf8.encode(fixture())),
      DateTime.now(),
      programmeCap: 1,
    );
    expect(parsed['d'], isTrue);
    expect((parsed['p'] as Map)['c'], hasLength(1));
    expect(((parsed['p'] as Map)['c'] as List).first[2], 'Past <title>');
  });
  test(
    'download handles redirect and gzip, stages cache and uses explicit headers',
    () async {
      final directory = await Directory.systemTemp.createTemp('epg-check-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final headers = <String?>[];
      server.listen((request) async {
        headers.add(request.headers.value(HttpHeaders.userAgentHeader));
        if (request.uri.path == '/redirect') {
          request.response.statusCode = 302;
          request.response.headers.set('location', '/guide');
        } else {
          request.response.headers.contentType = ContentType(
            'application',
            'xml',
          );
          request.response.headers.set('content-encoding', 'gzip');
          request.response.add(gzip.encode(utf8.encode(fixture())));
        }
        await request.response.close();
      });
      EpgGuideSnapshot? data;
      try {
        final path = '${directory.path}/cache.pending';
        final loaded = await EpgDownloadJob([
          'http://127.0.0.1:${server.port}/redirect',
        ], path).run();
        data = loaded;
        expect(loaded.programmeCount, 2);
        expect(loaded.programmesOf('c'), hasLength(2));
        expect(File('$path${Platform.pathSeparator}index.json').existsSync(), isTrue);
        expect(headers.every((h) => h == 'StellarTV/1.0'), true);
      } finally {
        data?.archive?.close();
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    '403 fallback is bounded; 401 does not retry or expose credentials',
    () async {
      final directory = await Directory.systemTemp.createTemp('epg-check-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var calls = 0;
      var status = 403;
      server.listen((request) async {
        calls++;
        request.response.statusCode = status;
        request.response.write('secret response');
        await request.response.close();
      });
      try {
        final url =
            'http://127.0.0.1:${server.port}/guide?username=private&password=secret';
        await expectLater(
          EpgDownloadJob([url], '${directory.path}/cache').run(),
          throwsA(
            isA<EpgDownloadException>().having(
              (e) => e.message,
              'message',
              'Guida non disponibile (HTTP 403).',
            ),
          ),
        );
        expect(calls, 3);
        status = 401;
        calls = 0;
        await expectLater(
          EpgDownloadJob([url], '${directory.path}/cache').run(),
          throwsA(
            isA<EpgDownloadException>().having(
              (e) => e.message,
              'message',
              'Guida non disponibile (HTTP 401).',
            ),
          ),
        );
        expect(calls, 1);
        expect(
          friendlyEpgError(Exception(url)).message,
          'La risposta non contiene una guida TV valida.',
        );
      } finally {
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'cancellation stops an in-flight guide without publishing a cache',
    () async {
      final directory = await Directory.systemTemp.createTemp('epg-check-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<void>();
      server.listen((request) {
        received.complete();
      });
      try {
        final path = '${directory.path}/cache.pending';
        final job = EpgDownloadJob([
          'http://127.0.0.1:${server.port}/guide',
        ], path);
        final result = job.run();
        final assertion = expectLater(
          result,
          throwsA(isA<EpgRefreshDeferred>()),
        );
        await received.future;
        job.cancel();
        await assertion;
        expect(await File(path).exists(), false);
      } finally {
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
  test('malformed HTML response cannot replace the existing guide', () async {
    final directory = await Directory.systemTemp.createTemp('epg-check-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.write('<html>Login</html>');
      await request.response.close();
    });
    try {
      final old = File('${directory.path}/cache');
      await old.writeAsString('existing');
      await expectLater(
        EpgDownloadJob([
          'http://127.0.0.1:${server.port}/guide',
        ], '${old.path}.pending').run(),
        throwsA(isA<EpgDownloadException>()),
      );
      expect(await old.readAsString(), 'existing');
    } finally {
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });

  test('an empty guide does not replace programmes or count as fresh', () {
    expect(
      epgKeepsPreviousGuide(previousCount: 40, incomingCount: 0),
      isTrue,
    );
    expect(
      epgKeepsPreviousGuide(previousCount: 0, incomingCount: 0),
      isFalse,
    );
    expect(epgGuideIsFresh(0), isFalse);
    expect(epgGuideIsFresh(3), isTrue);
    final now = DateTime.utc(2026, 10, 26, 22);
    expect(
      epgGuideNeedsRefresh(
        empty: false,
        programmeCount: 0,
        hasChannels: true,
        lastRun: now,
        intervalMinutes: 1440,
        now: now.add(const Duration(minutes: 10)),
      ),
      isTrue,
    );
    expect(
      epgGuideNeedsRefresh(
        empty: false,
        programmeCount: 12,
        hasChannels: true,
        lastRun: now,
        intervalMinutes: 1440,
        now: now.add(const Duration(minutes: 10)),
      ),
      isFalse,
    );
  });
}
