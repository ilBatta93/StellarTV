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

  /// Widget tests never touch files or the network.
  static final bool disabled = Platform.environment.containsKey('FLUTTER_TEST');

  void notifyAvailabilityChanged() => notifyListeners();

  T? valueOf(String key) => _values[key]?.$1;

  /// Plain copy safe to send across an isolate boundary.
  Map<String, T> snapshot() => {
    for (final entry in _values.entries) entry.key: entry.value.$1,
  };
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
            if (value != null) _values['$k'] = (value, v[1] as int);
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
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 3), _save);
  }

  Future<void> _save() async {
    try {
      final file = await _file();
      final data = {
        for (final e in _values.entries)
          e.key: [encode(e.value.$1), e.value.$2],
      };
      final path = file.path;
      await Isolate.run(() {
        final tmp = File('$path.tmp');
        tmp.writeAsStringSync(jsonEncode(data), flush: true);
        tmp.renameSync(path);
      });
    } catch (_) {}
  }
}
