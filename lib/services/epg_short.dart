import 'dart:convert';
import 'dart:io';

import '../models/epg_program.dart';
import 'epg_timeline.dart';

/// Numeric stream id used by the short listing call. Catalog ids are `live_`.
String? epgStreamId(String channelId) {
  const prefix = 'live_';
  if (!channelId.startsWith(prefix)) return null;
  final id = channelId.substring(prefix.length).trim();
  if (id.isEmpty || id.contains('/')) return null;
  return id;
}

String epgListingText(Object? raw) {
  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty) return '';
  try {
    final normalized = text.replaceAll(RegExp(r'\s+'), '');
    if (normalized.length < 4 || normalized.length % 4 != 0) return text;
    final decoded = utf8.decode(base64.decode(normalized));
    if (decoded.isEmpty) return text;
    final printable = decoded.runes.every(
      (unit) => unit == 9 || unit == 10 || unit == 13 || (unit >= 32 && unit != 0xFFFD),
    );
    return printable ? decoded : text;
  } catch (_) {
    return text;
  }
}

DateTime? epgListingTime(Object? stamp, Object? text) {
  final numeric = stamp is num
      ? stamp.toInt()
      : int.tryParse(stamp?.toString().trim() ?? '');
  if (numeric != null && numeric > 0) {
    final millis = numeric > 100000000000 ? numeric : numeric * 1000;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
  final raw = text?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  final iso = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
  return DateTime.tryParse(iso);
}

/// Listings from a short guide response. Titles are often base64 text.
List<EpgProgram> parseShortEpg(Object? json, String streamId) {
  final body = json is Map ? json['epg_listings'] : null;
  if (body is! List) return const [];
  final out = <EpgProgram>[];
  for (final row in body) {
    if (row is! Map) continue;
    final start = epgListingTime(row['start_timestamp'], row['start']);
    final end = epgListingTime(row['stop_timestamp'], row['end']);
    final title = epgListingText(row['title']);
    if (start == null || end == null || !end.isAfter(start) || title.isEmpty) {
      continue;
    }
    final description = epgListingText(row['description']);
    out.add(
      EpgProgram(
        id: '${streamId}_${start.millisecondsSinceEpoch}',
        channelId: streamId,
        title: title,
        description: description.length <= epgDescriptionLimit
            ? description
            : epgClipDescription(description),
        startTime: start,
        endTime: end,
      ),
    );
  }
  out.sort((a, b) => a.startTime.compareTo(b.startTime));
  return out;
}

class EpgShortGuide {
  /// One targeted listing. Failures return an empty list and never include
  /// the address or the account in the result.
  static Future<List<EpgProgram>> fetch({
    required String server,
    required String username,
    required String password,
    required String streamId,
    int limit = 80,
  }) async {
    var base = server.trim();
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      base = 'http://$base';
    }
    base = base.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/player_api.php').replace(
      queryParameters: {
        'username': username,
        'password': password,
        'action': 'get_short_epg',
        'stream_id': streamId,
        'limit': '${limit.clamp(1, 120)}',
      },
    );
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..userAgent = 'StellarTV/1.0';
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json, */*');
      request.headers.set(HttpHeaders.connectionHeader, 'close');
      final response = await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        await response.drain<void>().catchError((_) {});
        return const [];
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 12))) {
        bytes.addAll(chunk);
        if (bytes.length > 2 * 1024 * 1024) break;
      }
      final json = jsonDecode(utf8.decode(bytes));
      return parseShortEpg(json, streamId);
    } catch (_) {
      return const [];
    } finally {
      client.close(force: true);
    }
  }
}
