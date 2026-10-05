import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';

/// Keeps the last downloaded copy of every playlist section (Diretta, Film,
/// Serie TV) on disk, each in its own file: a section that downloads fine is
/// saved even when another one fails. Encoding and decoding run in a
/// background isolate so big playlists never freeze the interface.
class CatalogCacheService {
  static const sections = [
    ContentType.live,
    ContentType.movie,
    ContentType.series,
  ];

  int _hash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  Future<String> _dir() async =>
      (await getApplicationSupportDirectory()).path;

  String _sectionPath(String dir, String accountKey, ContentType type) =>
      '$dir/stellartv_catalog_v2_${_hash(accountKey)}_${type.name}.json';

  String _legacyPath(String dir, String accountKey) =>
      '$dir/stellartv_catalog_v1_${_hash(accountKey)}.json';

  /// All saved sections (falls back to the old single-file cache).
  Future<List<Channel>> read(String accountKey) async {
    try {
      final dir = await _dir();
      final paths = [
        for (final type in sections) _sectionPath(dir, accountKey, type),
      ];
      final legacy = _legacyPath(dir, accountKey);
      return await Isolate.run(() => _readFiles(paths, legacy));
    } catch (_) {
      return const [];
    }
  }

  Future<void> writeSection(
    String accountKey,
    ContentType type,
    List<Channel> channels,
  ) async {
    try {
      final dir = await _dir();
      final path = _sectionPath(dir, accountKey, type);
      final rows = [for (final c in channels) c.toMap()];
      await Isolate.run(() => _writeFile(path, rows));
    } catch (_) {
      // A cache write must never affect playback or catalog refresh.
    }
  }

  /// Kept for callers that save the whole playlist at once.
  Future<void> write(String accountKey, List<Channel> channels) async {
    for (final type in sections) {
      final part = channels
          .where(
            (c) =>
                c.type == type ||
                (type == ContentType.series && c.type == ContentType.anime),
          )
          .toList();
      if (part.isNotEmpty) await writeSection(accountKey, type, part);
    }
  }

  Future<void> clear(String accountKey) async {
    try {
      final dir = await _dir();
      for (final path in [
        _legacyPath(dir, accountKey),
        for (final type in sections) _sectionPath(dir, accountKey, type),
      ]) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    } catch (_) {}
  }
}

List<Channel> _readFiles(List<String> paths, String legacyPath) {
  final out = <Channel>[];
  var found = false;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! List) continue;
      found = true;
      for (final item in decoded) {
        if (item is Map) out.add(Channel.fromMap(item.cast<String, dynamic>()));
      }
    } catch (_) {
      // Corrupted section: ignore it, the next download replaces it.
    }
  }
  if (found) return out;
  final legacy = File(legacyPath);
  if (!legacy.existsSync()) return out;
  try {
    final decoded = jsonDecode(legacy.readAsStringSync());
    if (decoded is List) {
      for (final item in decoded) {
        if (item is Map) out.add(Channel.fromMap(item.cast<String, dynamic>()));
      }
    }
  } catch (_) {}
  return out;
}

void _writeFile(String path, List<Map<String, dynamic>> rows) {
  final file = File(path);
  final temporary = File('$path.tmp');
  temporary.writeAsStringSync(jsonEncode(rows), flush: true);
  temporary.renameSync(file.path);
}
