import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Small persistent per-title store (IMDb ratings, streaming providers).
/// Decoded off the UI thread, written debounced and atomically. Entries
/// stay valid for [ttl]; expired entries keep being shown until refreshed,
/// so nothing is ever rebuilt from scratch at app start.
class TitleMetadataStore<T> extends ChangeNotifier {
  final String fileName;
  final Duration ttl;
  final Object? Function(T value) encode;
  final T? Function(Object? raw) decode;
  TitleMetadataStore({
    required this.fileName,
    required this.encode,
    required this.decode,
    this.ttl = const Duration(days: 30),
  });

  final Map<String, (T, int)> _values = {};
  Future<void>? _loading;
  Timer? _saveTimer;
  bool _saving = false;

  /// Keys put since the last save. Encoding every value on each save held
  /// the TV's UI thread while a catalog was being scored.
  final Set<String> _changed = {};

  /// Widget tests never touch files or the network.
  static final bool disabled = Platform.environment.containsKey('FLUTTER_TEST');

  void notifyAvailabilityChanged() => notifyListeners();

  T? valueOf(String key) => _values[key]?.$1;

  /// Plain copy safe to send across an isolate boundary.
  Map<String, T> snapshot() => {
    for (final entry in _values.entries) entry.key: entry.value.$1,
  };

  /// Values with the device timestamp, for the local facet index.
  Map<String, (T, int)> timedSnapshot() => Map<String, (T, int)>.from(_values);
  bool isFresh(String key) {
    final at = _values[key]?.$2;
    return at != null &&
        DateTime.now().millisecondsSinceEpoch - at < ttl.inMilliseconds;
  }

  Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/$fileName');

  Future<void> load() => _loading ??= () async {
    if (disabled) return;
    try {
      final path = (await _file()).path;
      final raw = await Isolate.run(() {
        final f = File(path);
        if (!f.existsSync()) return null;
        return jsonDecode(f.readAsStringSync());
      });
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is List && v.length == 2 && v[1] is int) {
            final value = decode(v[0]);
            // A value put while the file was loading is newer.
            if (value != null && !_changed.contains('$k')) {
              _values['$k'] = (value, v[1] as int);
            }
          }
        });
        if (_values.isNotEmpty) notifyListeners();
      }
    } catch (_) {}
  }();

  void put(String key, T value) {
    _values[key] = (value, DateTime.now().millisecondsSinceEpoch);
    notifyListeners();
    if (disabled) return;
    _changed.add(key);
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 3), _save);
  }

  /// Writes only the changed keys: the isolate merges them into the file.
  Future<void> _save() async {
    if (_saving) {
      _scheduleSave();
      return;
    }
    if (_changed.isEmpty) return;
    _saving = true;
    final keys = _changed.toList(growable: false);
    _changed.clear();
    try {
      final path = (await _file()).path;
      final delta = <String, Object?>{
        for (final key in keys)
          if (_values[key] case final entry?) key: [encode(entry.$1), entry.$2],
      };
      // An unreadable file was replaced by the delta alone: the next save
      // writes every key again.
      if (!await Isolate.run(() => mergeJsonMapFile(path, delta))) {
        _changed.addAll(_values.keys);
      }
    } catch (_) {
      _changed.addAll(keys);
    } finally {
      _saving = false;
    }
    if (_changed.isNotEmpty) _scheduleSave();
  }
}

/// Merges [delta] into the JSON object saved at [path]. False when the
/// existing file could not be read, so it now holds [delta] only.
bool mergeJsonMapFile(String path, Map<String, Object?> delta) {
  var readable = true;
  Map<String, Object?> data = {};
  final file = File(path);
  if (file.existsSync()) {
    try {
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is Map<String, Object?>) {
        data = raw;
      } else {
        readable = false;
      }
    } catch (_) {
      readable = false;
    }
  }
  data.addAll(delta);
  final tmp = File('$path.tmp');
  tmp.writeAsStringSync(jsonEncode(data), flush: true);
  tmp.renameSync(path);
  return readable;
}
