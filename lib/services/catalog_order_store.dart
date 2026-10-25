import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'title_metadata_store.dart';

/// Remembers the IMDb order of each catalog view on the device.
/// Opening the same category again, or relaunching the app, reuses that
/// order instead of sorting from scratch.
class CatalogOrderStore extends ChangeNotifier {
  CatalogOrderStore._();
  static final instance = CatalogOrderStore._();

  static const _fileName = 'catalog_rating_order_v1.json';
  final Map<String, List<String>> _orders = {};
  Future<void>? _loading;
  Timer? _saveTimer;
  bool _loaded = false;

  List<String>? idsFor(String key) {
    final ids = _orders[key];
    if (ids == null || ids.isEmpty) return null;
    return ids;
  }

  Future<void> load() => _loading ??= _read();

  void save(String key, List<String> ids) {
    _orders[key] = List<String>.from(ids);
    if (TitleMetadataStore.disabled) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () {
      _saveTimer = null;
      unawaited(_write());
    });
  }

  Future<void> _read() async {
    if (TitleMetadataStore.disabled) return;
    try {
      final path = await _path();
      final raw = await Isolate.run(() {
        final file = File(path);
        if (!file.existsSync()) return null;
        return jsonDecode(file.readAsStringSync());
      });
      if (raw is! Map) return;
      var added = false;
      raw.forEach((key, value) {
        if (value is! List) return;
        final id = key.toString();
        if (_orders.containsKey(id)) return;
        _orders[id] = [for (final item in value) item.toString()];
        added = true;
      });
      _loaded = true;
      if (added) notifyListeners();
    } catch (_) {
      _loaded = true;
    }
  }

  Future<void> _write() async {
    try {
      final path = await _path();
      final data = {
        for (final entry in _orders.entries) entry.key: entry.value,
      };
      await Isolate.run(() {
        final tmp = File('$path.tmp');
        tmp.writeAsStringSync(jsonEncode(data), flush: true);
        tmp.renameSync(path);
      });
    } catch (_) {}
  }

  Future<String> _path() async =>
      '${(await getApplicationSupportDirectory()).path}/$_fileName';

  bool get loaded => _loaded;
}
