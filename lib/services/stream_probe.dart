import 'dart:async';
import 'dart:io';
import 'dart:convert';

/// Opt-in diagnostics only: after a live attempt fails without a picture,
/// reads what the server really sends (status, type, bytes, MPEG-TS sync,
/// playlist shape, first segment). Records numbers and fixed labels only:
/// never addresses, hosts, credentials or response text.
class StreamProbe {
  static const _budget = Duration(seconds: 4);

  static Future<Map<String, Object?>> run(String url, String userAgent) async {
    final out = <String, Object?>{};
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3)
      ..userAgent = userAgent;
    try {
      final first = await _fetch(client, Uri.parse(url), userAgent, 'probe', out)
          .timeout(_budget);
      if (first == null) return out;
      final (body, base) = first;
      final text = _ascii(body);
      if (!text.startsWith('#EXTM3U')) return out;
      out['playlistType'] =
          text.contains('#EXT-X-STREAM-INF') ? 'master' : 'media';
      final lines = const LineSplitter()
          .convert(text)
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList();
      out['playlistSegments'] = lines.length;
      final td = RegExp(r'#EXT-X-TARGETDURATION:(\d+)').firstMatch(text);
      if (td != null) out['targetDuration'] = int.parse(td.group(1)!);
      out['playlistLive'] = !text.contains('#EXT-X-ENDLIST');
      if (lines.isEmpty) return out;
      var next = base.resolve(lines.first);
      if (out['playlistType'] == 'master') {
        final variant = await _fetch(client, next, userAgent, 'variant', out)
            .timeout(_budget);
        if (variant == null) return out;
        final vt = _ascii(variant.$1);
        final seg = const LineSplitter()
            .convert(vt)
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && !l.startsWith('#'))
            .toList();
        out['variantSegments'] = seg.length;
        if (seg.isEmpty) return out;
        next = variant.$2.resolve(seg.first);
      }
      out['segHostChanged'] = next.host != Uri.parse(url).host;
      await _fetch(client, next, userAgent, 'seg', out).timeout(_budget);
    } on TimeoutException {
      out['probeTimeout'] = true;
    } catch (e) {
      out['probeFailure'] = e is SocketException
          ? 'socket'
          : e is HandshakeException
          ? 'tls'
          : e is HttpException
          ? 'http'
          : 'other';
    } finally {
      client.close(force: true);
    }
    return out;
  }

  /// Follows up to 5 redirects by hand; reads at most 3 s / 512 KB.
  static Future<(List<int>, Uri)?> _fetch(
    HttpClient client,
    Uri uri,
    String ua,
    String p,
    Map<String, Object?> out,
  ) async {
    final clock = Stopwatch()..start();
    var target = uri;
    for (var hops = 0; hops <= 5; hops++) {
      final req = await client.getUrl(target);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.userAgentHeader, ua);
      final res = await req.close();
      if (res.isRedirect) {
        final loc = res.headers.value(HttpHeaders.locationHeader);
        await res.drain<void>().catchError((_) {});
        if (loc == null) break;
        final nextUri = target.resolve(loc);
        out['${p}HostChanged'] = nextUri.host != uri.host;
        out['${p}Redirects'] = hops + 1;
        target = nextUri;
        continue;
      }
      out['${p}Status'] = res.statusCode;
      out['${p}FirstByteMs'] = clock.elapsedMilliseconds;
      out['${p}Kind'] = _kind(res.headers.contentType?.mimeType ?? '');
      final bytes = <int>[];
      final read = Stopwatch()..start();
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 3))) {
          bytes.addAll(chunk);
          if (bytes.length >= 512 * 1024 || read.elapsed.inSeconds >= 3) break;
        }
      } on TimeoutException {
        out['${p}ReadStalled'] = true;
      }
      out['${p}Bytes'] = bytes.length;
      out['${p}ReadMs'] = read.elapsedMilliseconds;
      out['${p}TsSync'] = tsSync(bytes);
      return (bytes, target);
    }
    return null;
  }

  static String _ascii(List<int> b) =>
      latin1.decode(b.take(64 * 1024).toList(), allowInvalid: true).trimLeft();

  static String _kind(String mime) {
    final m = mime.toLowerCase();
    if (m.contains('mpegurl')) return 'm3u8';
    if (m.contains('mp2t') || m.contains('mpegts')) return 'mpegts';
    if (m.startsWith('video/')) return 'video';
    if (m.contains('octet-stream')) return 'binary';
    if (m.contains('html')) return 'html';
    if (m.contains('json')) return 'json';
    if (m.startsWith('text/')) return 'text';
    return m.isEmpty ? 'none' : 'other';
  }

  /// True when the data is a real MPEG-TS stream (0x47 every 188 bytes).
  static bool tsSync(List<int> b) {
    for (var start = 0; start < 188 && start + 188 * 3 < b.length; start++) {
      if (b[start] == 0x47 &&
          b[start + 188] == 0x47 &&
          b[start + 376] == 0x47 &&
          b[start + 564] == 0x47) {
        return true;
      }
    }
    return false;
  }

  /// HTTP status quoted in a player error ("Response code: 403", "HTTP 509").
  static int? statusIn(String reason) {
    final m = RegExp(
      r'(?:response code|http(?: error)?|status)[:\s]*([1-5]\d\d)',
      caseSensitive: false,
    ).firstMatch(reason);
    return m == null ? null : int.parse(m.group(1)!);
  }
}
