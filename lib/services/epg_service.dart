import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/epg_program.dart';

/// Parsed guide: programmes grouped by XMLTV channel id, plus the
/// display names of each channel (used when the playlist has no tvg-id).
class EpgData {
  final Map<String, List<EpgProgram>> programmes;
  final Map<String, String> displayNames;
  final DateTime? fetchedAt;

  const EpgData({
    this.programmes = const {},
    this.displayNames = const {},
    this.fetchedAt,
  });

  bool get isEmpty => programmes.isEmpty;
  int get programmeCount =>
      programmes.values.fold(0, (sum, list) => sum + list.length);

  static EpgData fromJson(Map<String, dynamic> json) {
    final progs = <String, List<EpgProgram>>{};
    final raw = json['p'];
    if (raw is Map) {
      raw.forEach((id, list) {
        if (list is! List) return;
        final items = <EpgProgram>[];
        for (final e in list) {
          if (e is! List || e.length < 4) continue;
          items.add(EpgProgram(
            id: '${id}_${e[0]}',
            channelId: id.toString(),
            title: e[2].toString(),
            description: e[3].toString(),
            startTime: DateTime.fromMillisecondsSinceEpoch(e[0] as int),
            endTime: DateTime.fromMillisecondsSinceEpoch(e[1] as int),
          ));
        }
        progs[id.toString()] = items;
      });
    }
    final names = <String, String>{};
    final rawNames = json['n'];
    if (rawNames is Map) {
      rawNames.forEach((k, v) => names[k.toString()] = v.toString());
    }
    return EpgData(
      programmes: progs,
      displayNames: names,
      fetchedAt: DateTime.tryParse(json['t']?.toString() ?? ''),
    );
  }
}

/// Downloads and parses XMLTV guides (from the playlist and from sources
/// added by hand) and keeps a local copy so the guide is ready at startup.
class EpgService {
  static const _usePlaylistKey = 'epg_use_playlist';
  static const _sourcesKey = 'epg_sources';
  static const _intervalKey = 'epg_refresh_minutes';
  static const _lastRunKey = 'epg_last_run';

  Future<bool> usePlaylistGuide() async =>
      (await SharedPreferences.getInstance()).getBool(_usePlaylistKey) ?? true;

  Future<void> setUsePlaylistGuide(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_usePlaylistKey, value);

  Future<List<String>> manualSources() async =>
      (await SharedPreferences.getInstance()).getStringList(_sourcesKey) ??
      const [];

  Future<void> saveManualSources(List<String> urls) async =>
      (await SharedPreferences.getInstance()).setStringList(_sourcesKey, urls);

  /// Default: update the guide every 12 hours.
  Future<int> intervalMinutes() async =>
      (await SharedPreferences.getInstance()).getInt(_intervalKey) ?? 720;

  Future<void> saveIntervalMinutes(int minutes) async =>
      (await SharedPreferences.getInstance()).setInt(_intervalKey, minutes);

  Future<DateTime?> lastRun() async => DateTime.tryParse(
      (await SharedPreferences.getInstance()).getString(_lastRunKey) ?? '');

  Future<void> markRun() async => (await SharedPreferences.getInstance())
      .setString(_lastRunKey, DateTime.now().toIso8601String());

  File get _cacheFile =>
      File('${Directory.systemTemp.path}/stellartv_epg_cache_v1.json');

  Future<EpgData> loadCache() async {
    try {
      final file = _cacheFile;
      if (!await file.exists()) return const EpgData();
      final text = await file.readAsString();
      return await Isolate.run(() {
        final json = jsonDecode(text);
        return json is Map<String, dynamic>
            ? EpgData.fromJson(json)
            : const EpgData();
      });
    } catch (_) {
      return const EpgData();
    }
  }

  /// Downloads every source and merges them (first source wins per channel).
  /// Returns the merged guide; throws when no source could be read.
  Future<EpgData> fetch(List<String> urls) async {
    final merged = <String, dynamic>{'p': <String, dynamic>{}, 'n': <String, dynamic>{}};
    Object? lastError;
    var ok = 0;
    for (final url in urls) {
      try {
        final res = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 180));
        if (res.statusCode != 200) {
          throw HttpException('HTTP ${res.statusCode}');
        }
        final bytes = res.bodyBytes;
        final parsed = await Isolate.run(() => _parseXmltv(bytes));
        (parsed['p'] as Map<String, dynamic>).forEach((k, v) {
          (merged['p'] as Map<String, dynamic>).putIfAbsent(k, () => v);
        });
        (parsed['n'] as Map<String, dynamic>).forEach((k, v) {
          (merged['n'] as Map<String, dynamic>).putIfAbsent(k, () => v);
        });
        ok++;
      } catch (e) {
        lastError = e;
      }
    }
    if (ok == 0) {
      throw Exception(lastError == null
          ? 'Nessuna fonte EPG configurata'
          : 'Impossibile scaricare la guida TV');
    }
    merged['t'] = DateTime.now().toIso8601String();
    final text = jsonEncode(merged);
    try {
      await _cacheFile.writeAsString(text);
    } catch (_) {}
    return Isolate.run(() => EpgData.fromJson(
        jsonDecode(text) as Map<String, dynamic>));
  }
}

/// XMLTV parser (runs in an isolate). Keeps programmes from 2 hours ago to
/// 36 hours ahead to stay light on memory.
Map<String, dynamic> _parseXmltv(List<int> rawBytes) {
  var bytes = rawBytes;
  if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    bytes = gzip.decode(bytes);
  }
  final xml = utf8.decode(bytes, allowMalformed: true);
  final now = DateTime.now();
  final from = now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch;
  final to = now.add(const Duration(hours: 36)).millisecondsSinceEpoch;

  final names = <String, dynamic>{};
  final channelRe = RegExp(
      r'<channel\s+id="([^"]*)"[^>]*>([\s\S]*?)</channel>',
      caseSensitive: false);
  final nameRe = RegExp(r'<display-name[^>]*>([\s\S]*?)</display-name>',
      caseSensitive: false);
  for (final m in channelRe.allMatches(xml)) {
    final name = nameRe.firstMatch(m.group(2)!)?.group(1);
    if (name != null) names[_unescape(m.group(1)!)] = _unescape(name.trim());
  }

  final progs = <String, dynamic>{};
  final progRe = RegExp(r'<programme\b([^>]*)>([\s\S]*?)</programme>',
      caseSensitive: false);
  final attrRe = RegExp(r'(\w+)="([^"]*)"');
  final titleRe =
      RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false);
  final descRe = RegExp(r'<desc[^>]*>([\s\S]*?)</desc>', caseSensitive: false);
  for (final m in progRe.allMatches(xml)) {
    final attrs = <String, String>{
      for (final a in attrRe.allMatches(m.group(1)!)) a.group(1)!: a.group(2)!,
    };
    final start = _parseTime(attrs['start']);
    final stop = _parseTime(attrs['stop']);
    final channel = attrs['channel'];
    if (start == null || stop == null || channel == null) continue;
    if (stop < from || start > to) continue;
    final body = m.group(2)!;
    final title = titleRe.firstMatch(body)?.group(1);
    if (title == null) continue;
    final desc = descRe.firstMatch(body)?.group(1) ?? '';
    ((progs[_unescape(channel)] ??= <dynamic>[]) as List).add([
      start,
      stop,
      _unescape(title.trim()),
      _unescape(desc.trim()),
    ]);
  }
  for (final list in progs.values) {
    (list as List).sort((a, b) => (a[0] as int).compareTo(b[0] as int));
  }
  return {'p': progs, 'n': names};
}

/// XMLTV time: "20261004120000 +0200" (offset optional).
int? _parseTime(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*([+-]\d{4})?')
      .firstMatch(raw.trim());
  if (m == null) return null;
  final utc = DateTime.utc(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6) ?? '0'),
  );
  final offset = m.group(7);
  if (offset == null) return utc.millisecondsSinceEpoch;
  final sign = offset.startsWith('-') ? -1 : 1;
  final minutes =
      int.parse(offset.substring(1, 3)) * 60 + int.parse(offset.substring(3, 5));
  return utc
      .subtract(Duration(minutes: sign * minutes))
      .millisecondsSinceEpoch;
}

String _unescape(String s) => s
    .replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');
