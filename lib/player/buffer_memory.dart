import 'package:shared_preferences/shared_preferences.dart';

import '../models/live_buffer_policy.dart';

/// Remembers, per server, the forward buffer level that kept playback free
/// of stalls, so the next stream from a jittery server starts deep enough.
///
/// Only a hash of the host name is stored, on the device: no address, no
/// account, nothing that leaves the device.
class BufferMemory {
  BufferMemory._();

  static const _prefsKey = 'stellar_buffer_levels_v1';
  static const _maxEntries = 64;

  static final Map<String, int> _levels = {};
  static Future<void>? _loading;
  static var _ready = false;

  /// FNV-1a of the lower-case host: stable, short, not reversible to the
  /// address in practice.
  static String keyFor(String url) {
    final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
    if (host.isEmpty) return '';
    var hash = 0x811c9dc5;
    for (final unit in host.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static Future<void> ensureLoaded() {
    if (_ready) return Future<void>.value();
    return _loading ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        _levels.clear();
        for (final entry in prefs.getStringList(_prefsKey) ?? const []) {
          final parts = entry.split(':');
          final level = parts.length == 2 ? int.tryParse(parts[1]) : null;
          if (level != null) _levels[parts[0]] = level;
        }
      } catch (_) {}
      _ready = true;
    }();
  }

  static int levelFor(String url) =>
      (_levels[keyFor(url)] ?? 0).clamp(0, AdaptiveBuffer.maxLevel);

  static Future<void> remember(String url, int level) async {
    final key = keyFor(url);
    if (key.isEmpty) return;
    final value = level.clamp(0, AdaptiveBuffer.maxLevel);
    if (_levels[key] == value) return;
    _levels.remove(key);
    if (value > 0) _levels[key] = value;
    while (_levels.length > _maxEntries) {
      _levels.remove(_levels.keys.first);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, [
        for (final e in _levels.entries) '${e.key}:${e.value}',
      ]);
    } catch (_) {}
  }

  /// Settings "reset": every server starts again from the base buffer.
  static Future<void> clear() async {
    _levels.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }
}
