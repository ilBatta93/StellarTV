import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/dns_resolver_policy.dart';
import 'package:stellar_tv/services/dns_stream_proxy.dart';

Uint8List _answer({
  required int rcode,
  List<List<int>> a = const [],
  int ttl = 300,
}) {
  final b = BytesBuilder();
  b.add([0, 0, 0x81, 0x80 | rcode, 0, 1, 0, a.length, 0, 0, 0, 0]);
  b.add(DnsResolverPolicy.encodeQuery('example.com', 1).sublist(12));
  for (final ip in a) {
    // Compressed name pointing at the question (offset 12).
    b.add([0xc0, 12, 0, 1, 0, 1]);
    b.add([ttl >> 24, (ttl >> 16) & 0xff, (ttl >> 8) & 0xff, ttl & 0xff]);
    b.add([0, ip.length, ...ip]);
  }
  return b.toBytes();
}

void main() {
  group('scelta del DNS', () {
    test('di base usa un resolver senza filtri', () {
      final preset = DnsResolverPolicy.resolve(null)!;
      expect(preset.id, DnsResolverPolicy.defaultId);
      expect(preset.bootstrap, isNotEmpty);
    });

    test('il DNS del dispositivo non cambia nulla', () {
      expect(DnsResolverPolicy.resolve(DnsResolverPolicy.systemId), isNull);
    });

    test('una scelta sconosciuta torna al predefinito', () {
      expect(
        DnsResolverPolicy.resolve('vecchio')!.id,
        DnsResolverPolicy.defaultId,
      );
    });

    test('ogni preset ha indirizzi IP fissi per raggiungerlo', () {
      for (final p in DnsResolverPolicy.presets) {
        expect(p.bootstrap, isNotEmpty, reason: p.id);
        for (final ip in p.bootstrap) {
          expect(InternetAddress.tryParse(ip), isNotNull, reason: ip);
        }
      }
    });

    test('indirizzo personalizzato', () {
      final p = DnsResolverPolicy.parseCustomUrl('dns.esempio.it')!;
      expect(p.endpoint.toString(), 'https://dns.esempio.it/dns-query');
      expect(DnsResolverPolicy.parseCustomUrl('http://dns.esempio.it'), isNull);
      expect(DnsResolverPolicy.parseCustomUrl(''), isNull);
      expect(
        DnsResolverPolicy.resolve(
          DnsResolverPolicy.customId,
          customUrl: 'https://1.2.3.4/q',
        )!.bootstrap,
        ['1.2.3.4'],
      );
      // An unusable custom address keeps the default, never the system DNS.
      expect(
        DnsResolverPolicy.resolve(DnsResolverPolicy.customId)!.id,
        DnsResolverPolicy.defaultId,
      );
    });

    test('nomi locali e IP non passano dal resolver', () {
      for (final h in [
        '192.168.1.10',
        '[::1]',
        'localhost',
        'nas',
        'tv.local',
        'router.lan',
      ]) {
        expect(DnsResolverPolicy.bypasses(h), isTrue, reason: h);
      }
      expect(DnsResolverPolicy.bypasses('server.example.com'), isFalse);
    });
  });

  group('formato DNS', () {
    test('la domanda è codificata secondo RFC 8484', () {
      final q = DnsResolverPolicy.encodeQuery('example.com', 1);
      expect(
        q,
        [0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0] +
            [7, ...'example'.codeUnits, 3, ...'com'.codeUnits, 0] +
            [0, 1, 0, 1],
      );
    });

    test('legge indirizzi e TTL minimo', () {
      final answer = DnsResolverPolicy.decodeAnswer(
        _answer(
          rcode: 0,
          a: [
            [93, 184, 215, 14],
            [1, 2, 3, 4],
          ],
          ttl: 120,
        ),
        DnsResolverPolicy.typeA,
      );
      expect(answer.addresses.map(InternetAddress.fromRawAddress).toList(), [
        InternetAddress('93.184.215.14'),
        InternetAddress('1.2.3.4'),
      ]);
      expect(answer.ttlSeconds, 120);
    });

    test('nome inesistente: nessun indirizzo, nessun errore', () {
      expect(
        DnsResolverPolicy.decodeAnswer(
          _answer(rcode: 3),
          DnsResolverPolicy.typeA,
        ).addresses,
        isEmpty,
      );
    });

    test('errore del server e risposta troncata sono errori', () {
      expect(
        () => DnsResolverPolicy.decodeAnswer(
          _answer(rcode: 2),
          DnsResolverPolicy.typeA,
        ),
        throwsFormatException,
      );
      final full = _answer(
        rcode: 0,
        a: [
          [1, 2, 3, 4],
        ],
      );
      expect(
        () => DnsResolverPolicy.decodeAnswer(
          full.sublist(0, full.length - 2),
          DnsResolverPolicy.typeA,
        ),
        throwsFormatException,
      );
    });

    test('la cache resta fra 1 minuto e 1 ora', () {
      expect(DnsResolverPolicy.cacheFor(5), const Duration(minutes: 1));
      expect(DnsResolverPolicy.cacheFor(86400), const Duration(hours: 1));
    });
  });

  test('il proxy dei flussi inoltra la richiesta e chiude', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      req.response
        ..headers.set('x-path', req.uri.toString())
        ..headers.set('x-connection', req.headers.value('connection') ?? '')
        ..write('ok ${req.headers.value('user-agent')}')
        ..close();
    });
    final proxy = await DnsStreamProxy.start(DnsResolverPolicy.resolve(null)!);
    final client = HttpClient()
      ..userAgent = 'prova'
      ..findProxy = ((_) => 'PROXY 127.0.0.1:${proxy.port}');
    try {
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/live/1.ts?a=b'),
      );
      final res = await req.close();
      expect(res.statusCode, 200);
      expect(res.headers.value('x-path'), '/live/1.ts?a=b');
      expect(res.headers.value('x-connection'), 'close');
      expect(await res.transform(utf8.decoder).join(), 'ok prova');
    } finally {
      client.close(force: true);
      proxy.stop();
      await server.close(force: true);
    }
  });
}
