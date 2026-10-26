import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import 'playback_work_policy.dart';

/// Keeps the last downloaded copy of every playlist section (Diretta, Film,
/// Serie TV) on disk, each in its own file: a section that downloads fine is
/// saved even when another one fails.
///
/// Format v3 stores one title per line (NDJSON) closed by an end marker, so:
/// - encoding and the temporary file run in a background isolate, and only
///   when no session is open and the app is visible;
/// - the previous file is replaced only after that temporary copy is complete,
///   so a power loss, a full disk or a refused write can never empty a section;
/// - reading streams line by line in a background isolate whose result is
///   handed over without copying, keeping the memory peak low on TV boxes.
/// Older v2/v1 copies stay readable until a verified v3 file replaces them.
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

  /// Saves one section. Returns false, and leaves the previous file in place,
  /// when a session is open, the app is hidden, [stillAllowed] refuses, or
  /// the temporary copy does not finish.
  Future<bool> writeSection(
    String accountKey,
    ContentType type,
    List<Channel> channels, {
    bool Function()? stillAllowed,
  }) async {
    bool allowed() =>
        !PlaybackWorkPolicy.instance.blocksCatalogWrite &&
        (stillAllowed?.call() ?? true);
    try {
      if (!allowed()) return false;
      final dir = await _dir();
      if (!allowed()) return false;
      final ok = await writeCatalogFile(
        _v3Path(dir, accountKey, type),
        channels,
        stillAllowed: allowed,
      );
      if (!ok) return false;
      // The verified v3 copy replaces the older format of this section.
      // A session that opened after the replace only skips this small delete.
      if (allowed()) {
        final old = File(_sectionPath(dir, accountKey, type));
        if (await old.exists()) await old.delete();
      }
      return true;
    } catch (_) {
      // A cache write must never affect playback or catalog refresh.
      return false;
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

/// Encodes [channels] as NDJSON in a background isolate and replaces [path]
/// only when the temporary copy is complete. [stillAllowed] is checked before
/// the isolate starts and again before the replace, so a session that opens
/// in between keeps the previous file. Returns false and leaves that file
/// untouched on any failure.
Future<bool> writeCatalogFile(
  String path,
  List<Channel> channels, {
  bool Function()? stillAllowed,
}) async {
  if (stillAllowed != null && !stillAllowed()) return false;
  // Let the frame that closed the player paint before the list is copied
  // into the writer isolate.
  await Future<void>.delayed(Duration.zero);
  if (stillAllowed != null && !stillAllowed()) return false;
  final snapshot = List<Channel>.of(channels, growable: false);
  final temporary = File('$path.tmp');
  try {
    await _deleteIfPresent(temporary);
    if (stillAllowed != null && !stillAllowed()) return false;
    final count = await Isolate.run(
      () => _writeCatalogTempFile(temporary.path, snapshot),
    );
    final complete = count == snapshot.length && await temporary.exists();
    if (!complete || (stillAllowed != null && !stillAllowed())) {
      await _deleteIfPresent(temporary);
      return false;
    }
    await temporary.rename(path);
    return true;
  } catch (_) {
    await _deleteIfPresent(temporary);
    return false;
  }
}

/// Writes a complete v3 temporary file. Returns the title count, or -1 after
/// deleting [path] when the copy did not finish.
Future<int> _writeCatalogTempFile(String path, List<Channel> channels) async {
  final temporary = File(path);
  IOSink? sink;
  try {
    sink = temporary.openWrite();
    sink.writeln(jsonEncode({'stellar_catalog': CatalogCacheService._format}));
    final buffer = StringBuffer();
    var count = 0;
    for (final channel in channels) {
      buffer
        ..write(jsonEncode(channel.toMap()))
        ..write('\n');
      count++;
      if (buffer.length >= 64 * 1024) {
        sink.write(buffer.toString());
        buffer.clear();
      }
    }
    buffer
      ..write(jsonEncode({'end': count}))
      ..write('\n');
    sink.write(buffer.toString());
    await sink.flush();
    await sink.close();
    sink = null;
    if (count != channels.length) {
      await _deleteIfPresent(temporary);
      return -1;
    }
    return count;
  } catch (_) {
    try {
      await sink?.close();
    } catch (_) {}
    await _deleteIfPresent(temporary);
    return -1;
  }
}

Future<void> _deleteIfPresent(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } catch (_) {}
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
