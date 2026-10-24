import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';

/// Keeps the last downloaded copy of every playlist section (Diretta, Film,
/// Serie TV) on disk, each in its own file: a section that downloads fine is
/// saved even when another one fails.
///
/// Format v3 stores one title per line (NDJSON) closed by an end marker, so:
/// - writing never builds one giant string nor copies the whole catalog into
///   another isolate: titles are encoded in small time-sliced batches that
///   leave every frame to the interface;
/// - reading streams line by line in a background isolate whose result is
///   handed over without copying, keeping the memory peak low on TV boxes;
/// - a file without its end marker (power loss, full disk) is ignored and the
///   previous copy is used instead, so a broken save can never empty a
///   section. Older v2/v1 copies stay readable until v3 replaces them.
class CatalogCacheService {
  static const sections = [
    ContentType.live,
    ContentType.movie,
    ContentType.series,
  ];

  static const _format = 3;

  int _hash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  Future<String> _dir() async => (await getApplicationSupportDirectory()).path;

  String _v3Path(String dir, String accountKey, ContentType type) =>
      '$dir/stellartv_catalog_v3_${_hash(accountKey)}_${type.name}.ndjson';

  String _sectionPath(String dir, String accountKey, ContentType type) =>
      '$dir/stellartv_catalog_v2_${_hash(accountKey)}_${type.name}.json';

  String _legacyPath(String dir, String accountKey) =>
      '$dir/stellartv_catalog_v1_${_hash(accountKey)}.json';

  /// All saved sections (falls back to older formats per section).
  Future<List<Channel>> read(String accountKey) async {
    try {
      final dir = await _dir();
      final paths = [
        for (final type in sections)
          (_v3Path(dir, accountKey, type), _sectionPath(dir, accountKey, type)),
      ];
      final legacy = _legacyPath(dir, accountKey);
      return await Isolate.run(() => readCatalogFiles(paths, legacy));
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
      final ok = await writeCatalogFile(
        _v3Path(dir, accountKey, type),
        List<Channel>.of(channels, growable: false),
      );
      if (!ok) return;
      // The verified v3 copy replaces the older format of this section.
      final old = File(_sectionPath(dir, accountKey, type));
      if (await old.exists()) await old.delete();
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
        for (final type in sections) ...[
          _sectionPath(dir, accountKey, type),
          _v3Path(dir, accountKey, type),
          '${_v3Path(dir, accountKey, type)}.tmp',
        ],
      ]) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    } catch (_) {}
  }
}

/// Writes [channels] as NDJSON in time-sliced batches (about 6 ms of encoding
/// per event-loop turn), then atomically replaces [path]. Returns false and
/// leaves the previous copy untouched on any failure.
Future<bool> writeCatalogFile(
  String path,
  List<Channel> channels, {
  Duration slice = const Duration(milliseconds: 6),
}) async {
  final temporary = File('$path.tmp');
  IOSink? sink;
  try {
    sink = temporary.openWrite();
    sink.writeln(jsonEncode({'stellar_catalog': CatalogCacheService._format}));
    final clock = Stopwatch()..start();
    final buffer = StringBuffer();
    for (final c in channels) {
      buffer
        ..write(jsonEncode(c.toMap()))
        ..write('\n');
      if (buffer.length > 64 * 1024) {
        sink.write(buffer.toString());
        buffer.clear();
      }
      if (clock.elapsed >= slice) {
        await Future<void>.delayed(Duration.zero);
        clock.reset();
      }
    }
    buffer.write(jsonEncode({'end': channels.length}));
    buffer.write('\n');
    sink.write(buffer.toString());
    await sink.flush();
    await sink.close();
    sink = null;
    await temporary.rename(path);
    return true;
  } catch (_) {
    try {
      await sink?.close();
    } catch (_) {}
    try {
      if (await temporary.exists()) await temporary.delete();
    } catch (_) {}
    return false;
  }
}

/// Reads one v3 file; null when missing, unknown or incomplete.
Future<List<Channel>?> readCatalogFileV3(String path) async {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    final out = <Channel>[];
    var header = false;
    int? end;
    await for (final line
        in file
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.isEmpty) continue;
      if (end != null) return null; // data after the end marker
      final value = jsonDecode(line);
      if (!header) {
        if (value is! Map || value['stellar_catalog'] != 3) return null;
        header = true;
        continue;
      }
      if (value is Map && value.length == 1 && value['end'] is int) {
        end = value['end'] as int;
        continue;
      }
      if (value is Map) out.add(Channel.fromMap(value.cast<String, dynamic>()));
    }
    if (end == null || end != out.length) return null;
    return out;
  } catch (_) {
    return null;
  }
}

List<Channel>? _readJsonList(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! List) return null;
    return [
      for (final item in decoded)
        if (item is Map) Channel.fromMap(item.cast<String, dynamic>()),
    ];
  } catch (_) {
    return null;
  }
}

/// Per section: verified v3 first, then the v2 copy; v1 only when no section
/// exists at all.
Future<List<Channel>> readCatalogFiles(
  List<(String, String)> sections,
  String legacyPath,
) async {
  final out = <Channel>[];
  var found = false;
  for (final (v3, v2) in sections) {
    final rows = await readCatalogFileV3(v3) ?? _readJsonList(v2);
    if (rows == null) continue;
    found = true;
    out.addAll(rows);
  }
  if (found) return out;
  return _readJsonList(legacyPath) ?? out;
}
