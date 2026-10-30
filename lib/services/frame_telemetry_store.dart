import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// Private local checkpoints. One writer, one pending latest snapshot, two files.
class FrameTelemetryStore {
  FrameTelemetryStore(this.directory);
  final String directory;
  static const maxBytes = 256 * 1024;
  Map<String, Object?>? _pending;
  Future<void>? _writer;
  Future<Map<String, Object?>?>? _recovery;

  Future<Map<String, Object?>?> recover() =>
      _recovery ??= Isolate.run(() async {
        final dir = Directory(directory);
        await dir.create(recursive: true);
        final current = File('${dir.path}/telemetry_current.json');
        final previous = File('${dir.path}/telemetry_previous.json');
        Future<Map<String, Object?>?> read(File file) async {
          try {
            if (!await file.exists() || await file.length() > maxBytes) {
              return null;
            }
            final value = jsonDecode(await file.readAsString());
            if (value is! Map ||
                value['kind'] != 'performance' ||
                (value['v'] != 2 && value['v'] != 3)) {
              return null;
            }
            return Map<String, Object?>.from(value);
          } catch (_) {
            return null;
          }
        }

        final saved = await read(current);
        if (saved == null) return read(previous);
        // Commit recovery before retiring current. Failure leaves the only checkpoint intact.
        await _atomicWrite(previous.path, saved);
        await current.delete();
        return saved;
      });

  Future<void> save(Map<String, Object?> report) {
    _pending = report;
    return _writer ??= _drain().whenComplete(() => _writer = null);
  }

  Future<void> _drain() async {
    await recover();
    while (_pending != null) {
      final next = _pending;
      _pending = null;
      if (next == null) continue;
      final path = '$directory/telemetry_current.json';
      await Isolate.run(() => _atomicWrite(path, next));
    }
  }

  static Future<void> _atomicWrite(
    String path,
    Map<String, Object?> report,
  ) async {
    final bytes = utf8.encode(jsonEncode(report));
    if (bytes.length > maxBytes) {
      throw const FormatException('checkpoint too large');
    }
    await File(path).parent.create(recursive: true);
    final temporary = File('$path.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(path);
  }
}
