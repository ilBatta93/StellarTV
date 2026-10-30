import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stellar_tv/services/movie_hash.dart';

void main() {
  final head = Uint8List.fromList(List.generate(65536, (i) => i % 251));
  final tail = Uint8List.fromList(List.generate(65536, (i) => (i * 7) % 256));

  test('hash matches the OpenSubtitles reference algorithm', () {
    expect(MovieHash.compute(200000, head, tail), 'ba35b030ac289403');
  });

  test('reads only the first and last 64 KiB through Range', () async {
    final ranges = <String>[];
    final client = MockClient((req) async {
      final r = req.headers['Range']!;
      ranges.add(r);
      return http.Response.bytes(
        r == 'bytes=0-65535' ? head : tail,
        206,
        headers: {
          'content-range': '$r/200000'.replaceFirst('bytes=', 'bytes '),
        },
      );
    });
    final h = await MovieHash.fromUrl('http://x/movie.mkv', client: client);
    expect(h?.hash, 'ba35b030ac289403');
    expect(h?.size, 200000);
    expect(ranges, ['bytes=0-65535', 'bytes=134464-199999']);
  });

  test('servers ignoring Range fall back to title matching', () async {
    final client = MockClient((_) async => http.Response('x', 200));
    expect(
      await MovieHash.fromUrl('http://x/movie.mkv', client: client),
      isNull,
    );
    expect(
      await MovieHash.fromUrl('http://x/live.m3u8', client: client),
      isNull,
    );
  });
}
