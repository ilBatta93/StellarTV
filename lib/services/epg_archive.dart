import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../models/epg_data.dart';
import '../models/epg_program.dart';
import 'epg_prefix_index.dart';
import 'epg_timeline.dart';

String _child(String directory, String name) {
  if (directory.endsWith('/') || directory.endsWith(r'\')) return '$directory$name';
  return '$directory${Platform.pathSeparator}$name';
}

/// Random-access guide: one index plus a byte range per channel.
class EpgArchive {
  EpgArchive(this.directory, this.offsets, this.lengths, List<String> channelIds)
    : _at = {
        for (
          var i = 0;
          i < channelIds.length && i < offsets.length && i < lengths.length;
          i++
        )
          channelIds[i]: i,
      };

  String directory;
  final List<int> offsets;
  final List<int> lengths;
  final Map<String, int> _at;
  final LinkedHashMap<String, List<EpgProgram>> _cache = LinkedHashMap();
  RandomAccessFile? _slots;
  static const _cacheLimit = 16;

  String get _slotsPath => _child(directory, 'slots.bin');
  String get wordsPath => _child(directory, 'words.json');

  List<EpgProgram> read(String id) {
    final cached = _cache.remove(id);
    if (cached != null) {
      _cache[id] = cached;
      return cached;
    }
    final index = _at[id];
    if (index == null) return const [];
    final offset = offsets[index];
    final length = lengths[index];
    if (offset < 0 || length <= 0) return const [];
    try {
      final file = _slots ??= File(_slotsPath).openSync();
      file.setPositionSync(offset);
      final programmes = decodeEpgChannel(id, file.readSync(length));
      _cache[id] = programmes;
      while (_cache.length > _cacheLimit) {
        _cache.remove(_cache.keys.first);
      }
      return programmes;
    } catch (_) {
      return const [];
    }
  }

  Future<EpgPrefixIndex> loadPrefix() {
    final path = wordsPath;
    return Isolate.run(() => readEpgPrefixFile(path));
  }

  void retarget(String directory) {
    close();
    this.directory = directory;
  }

  void close() {
    final file = _slots;
    _slots = null;
    _cache.clear();
    if (file == null) return;
    try {
      file.closeSync();
    } catch (_) {}
  }
}

/// Header plus the channel file. Programme lists are not copied onto the
/// UI isolate.
class EpgGuideSnapshot {
  final EpgData data;
  final EpgArchive? archive;
  const EpgGuideSnapshot(this.data, this.archive);

  static const empty = EpgGuideSnapshot(EpgData(), null);

  int get programmeCount => data.programmeCount;
  bool get isEmpty => data.isEmpty;
  DateTime? get fetchedAt => data.fetchedAt;
  bool get degraded => data.degraded;

  List<EpgProgram> programmesOf(String id) =>
      archive?.read(id) ?? data.programmes[id] ?? const [];

  factory EpgGuideSnapshot.fromHeader(Map<dynamic, dynamic> header) {
    final names = <String, String>{};
    final rawNames = header['n'];
    if (rawNames is Map) {
      rawNames.forEach((key, value) {
        final text = value?.toString() ?? '';
        if (text.isNotEmpty) names[key.toString()] = text;
      });
    }
    final channels = <String>[
      for (final id in header['channels'] is List ? header['channels'] as List : const [])
        id.toString(),
    ];
    final data = EpgData(
      displayNames: names,
      fetchedAt: DateTime.tryParse(header['t']?.toString() ?? ''),
      degraded: header['d'] == true,
      declaredCount: header['count'] is num ? (header['count'] as num).toInt() : 0,
      channelIndex: List.unmodifiable(channels),
    );
    final dir = header['dir']?.toString();
    if (dir == null || dir.isEmpty) return EpgGuideSnapshot(data, null);
    return EpgGuideSnapshot(
      data,
      EpgArchive(dir, _nums(header['off']), _nums(header['len']), channels),
    );
  }
}

List<EpgProgram> decodeEpgChannel(String id, List<int> bytes) {
  final raw = jsonDecode(utf8.decode(bytes));
  if (raw is! List) return const [];
  return List<EpgProgram>.unmodifiable([
    for (final row in raw)
      if (row is List && row.length >= 4 && row[0] is num && row[1] is num)
        EpgProgram(
          id: '${id}_${(row[0] as num).toInt()}',
          channelId: id,
          title: row[2].toString(),
          description: row[3].toString(),
          startTime: DateTime.fromMillisecondsSinceEpoch((row[0] as num).toInt()),
          endTime: DateTime.fromMillisecondsSinceEpoch((row[1] as num).toInt()),
        ),
  ]);
}

/// Writes `directory` atomically (a sibling `.part` is renamed into place).
/// Returns a header the UI isolate can keep without the programme bodies.
Map<String, Object?> writeEpgArchive(String directory, Map<String, dynamic> parsed) {
  final part = '$directory.part';
  final partDir = Directory(part);
  if (partDir.existsSync()) partDir.deleteSync(recursive: true);
  partDir.createSync(recursive: true);
  final programmes = <String, List<List<Object?>>>{};
  final rawProgrammes = parsed['p'];
  if (rawProgrammes is Map) {
    rawProgrammes.forEach((key, value) {
      if (value is! List) return;
      final rows = <List<Object?>>[];
      for (final row in value) {
        if (row is List && row.length >= 4 && row[0] is num && row[1] is num) {
          rows.add(row);
        }
      }
      if (rows.isEmpty) return;
      rows.sort((a, b) => (a[0] as num).compareTo(b[0] as num));
      programmes[key.toString()] = rows;
    });
  }
  final names = <String, String>{};
  final rawNames = parsed['n'];
  if (rawNames is Map) {
    rawNames.forEach((key, value) {
      final text = value?.toString() ?? '';
      if (text.isNotEmpty) names[key.toString()] = text;
    });
  }
  final channels = <String>[...programmes.keys];
  final seen = channels.toSet();
  for (final id in names.keys) {
    if (seen.add(id)) channels.add(id);
  }
  final slots = File(_child(part, 'slots.bin')).openSync(mode: FileMode.write);
  final offsets = <int>[];
  final lengths = <int>[];
  final texts = <List<String>>[];
  var cursor = 0;
  var count = 0;
  try {
    for (final id in channels) {
      final words = <String>[id];
      final name = names[id];
      if (name != null) words.add(name);
      final rows = programmes[id];
      if (rows == null) {
        offsets.add(-1);
        lengths.add(0);
        texts.add(words);
        continue;
      }
      final payload = <List<Object?>>[];
      for (final row in rows) {
        final title = row[2].toString().trim();
        if (title.isEmpty) continue;
        words.add(title);
        final description = row[3]?.toString() ?? '';
        payload.add([
          (row[0] as num).toInt(),
          (row[1] as num).toInt(),
          title,
          description.length <= epgDescriptionLimit
              ? description
              : epgClipDescription(description),
        ]);
      }
      if (payload.isEmpty) {
        offsets.add(-1);
        lengths.add(0);
        texts.add(words);
        continue;
      }
      final bytes = utf8.encode(jsonEncode(payload));
      slots.writeFromSync(bytes);
      offsets.add(cursor);
      lengths.add(bytes.length);
      cursor += bytes.length;
      count += payload.length;
      texts.add(words);
    }
  } finally {
    slots.closeSync();
  }
  final prefix = EpgPrefixIndex.build(texts);
  File(_child(part, 'words.json')).writeAsStringSync(
    jsonEncode(prefix.toJson()),
    flush: true,
  );
  final index = <String, Object?>{
    'v': 3,
    't': parsed['t']?.toString() ?? DateTime.now().toIso8601String(),
    'd': parsed['d'] == true,
    'count': count,
    'n': names,
    'channels': channels,
    'off': offsets,
    'len': lengths,
  };
  File(_child(part, 'index.json')).writeAsStringSync(jsonEncode(index), flush: true);
  final dest = Directory(directory);
  if (dest.existsSync()) dest.deleteSync(recursive: true);
  partDir.renameSync(directory);
  return {...index, 'dir': directory};
}

/// Startup read. A legacy single-file cache is rewritten as a channel index
/// inside this call, so the UI isolate never decodes the old blob.
Map<String, Object?>? loadEpgCacheHeader(String support, String key) {
  final separator = Platform.pathSeparator;
  final directory = '$support${separator}stellartv_epg_v3_$key';
  final indexFile = File(_child(directory, 'index.json'));
  if (indexFile.existsSync()) {
    final header = _readIndex(indexFile);
    if (header != null) {
      header['dir'] = directory;
      return header;
    }
  }
  final legacy = File('$support${separator}stellartv_epg_v2_$key.json');
  if (!legacy.existsSync()) return null;
  try {
    final decoded = jsonDecode(legacy.readAsStringSync());
    if (decoded is! Map) return null;
    final data = EpgData.fromJson(
      Map<String, dynamic>.from(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      ),
    );
    final header = writeEpgArchive(directory, {
      't': data.fetchedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'd': false,
      'n': data.displayNames,
      'p': {
        for (final entry in data.programmes.entries)
          entry.key: [
            for (final program in entry.value)
              [
                program.startTime.millisecondsSinceEpoch,
                program.endTime.millisecondsSinceEpoch,
                program.title,
                program.description,
              ],
          ],
      },
    });
    try {
      legacy.deleteSync();
    } catch (_) {}
    return header;
  } catch (_) {
    return null;
  }
}

Map<String, Object?>? _readIndex(File file) {
  try {
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map || json['v'] != 3) return null;
    return json.map((key, value) => MapEntry(key.toString(), value));
  } catch (_) {
    return null;
  }
}

List<int> _nums(Object? raw) =>
    raw is List ? [for (final value in raw) if (value is num) value.toInt()] : const [];
