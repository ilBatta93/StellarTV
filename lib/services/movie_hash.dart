import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// OpenSubtitles "moviehash": file size plus the 64-bit little-endian sum
/// of the first and last 64 KiB. Only two small HTTP Range reads are made,
/// so the full video is never downloaded.
class MovieHash {
  static const chunk = 65536;

  final String hash;
  final int size;
  const MovieHash(this.hash, this.size);

  /// Pure computation, shared by tests and the network reader.
  static String compute(int size, Uint8List head, Uint8List tail) {
    if (head.length < chunk || tail.length < chunk) {
      throw ArgumentError('servono 64 KiB iniziali e finali');
    }
    var sum = BigInt.from(size);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final bytes in [head, tail]) {
      final view = ByteData.sublistView(bytes, 0, chunk);
      for (var i = 0; i < chunk; i += 8) {
        final lo = BigInt.from(view.getUint32(i, Endian.little));
        final hi = BigInt.from(view.getUint32(i + 4, Endian.little));
        sum = (sum + (hi << 32) + lo) & mask;
      }
    }
    return sum.toRadixString(16).padLeft(16, '0');
  }

  static int? _totalFrom(String? contentRange) {
    final m = RegExp(r'/(\d+)\s*$').firstMatch(contentRange ?? '');
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// Returns null when the server ignores Range (live/HLS) or the file is
  /// too small: the caller then falls back to title matching.
  static Future<MovieHash?> fromUrl(
    String url, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isScheme('http') && !uri.isScheme('https')) {
      return null;
    }
    if (uri.path.toLowerCase().endsWith('.m3u8')) return null;
    final c = client ?? http.Client();
    try {
      Future<http.Response> range(int start, int end) => c
          .get(uri, headers: {'Range': 'bytes=$start-$end'})
          .timeout(timeout);
      final first = await range(0, chunk - 1);
      if (first.statusCode != 206 || first.bodyBytes.length < chunk) {
        return null;
      }
      final size = _totalFrom(first.headers['content-range']);
      if (size == null || size < chunk * 2) return null;
      final last = await range(size - chunk, size - 1);
      if (last.statusCode != 206 || last.bodyBytes.length < chunk) return null;
      return MovieHash(compute(size, first.bodyBytes, last.bodyBytes), size);
    } catch (_) {
      return null;
    } finally {
      if (client == null) c.close();
    }
  }
}
