import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tmdb_item.dart';

/// Timestamped per-profile reactions; neutral entries are tombstones for sync.
class ReactionsProvider extends ChangeNotifier {
  static const storageKey = 'profile_reactions_v1';
  String? _profile;
  Map<String, dynamic> _all = {};
  Future<void> _writes = Future.value();
  VoidCallback? onSaved;
  int _generation = 0;
  String get scope => _profile ?? '_default';
  Map<String, dynamic> get _entries =>
      Map<String, dynamic>.from(_all[scope] as Map? ?? {});
  int vote(TmdbItem item) => (_entries[item.key] as Map?)?['vote'] as int? ?? 0;
  String get signature => '$scope:${jsonEncode(_entries)}';
  List<TmdbItem> get liked => [
    for (final e in _entries.values)
      if (e is Map && e['vote'] == 1 && e['item'] is Map)
        TmdbItem.tryParse(Map<String, dynamic>.from(e['item'] as Map)),
  ].whereType<TmdbItem>().toList();
  Set<String> get disliked => {
    for (final e in _entries.entries)
      if (e.value is Map && e.value['vote'] == -1) e.key,
  };
  Future<void> switchProfile(String? id) async {
    _profile = id;
    _generation++;
    notifyListeners();
    await reload();
  }

  Future<void> reload() async {
    final gen = _generation;
    await _writes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (gen != _generation) return;
    try {
      _all = Map<String, dynamic>.from(
        jsonDecode(prefs.getString(storageKey) ?? '{}') as Map,
      );
    } catch (_) {
      _all = {};
    }
    notifyListeners();
  }

  Future<void> setVote(TmdbItem item, int value) {
    _generation++;
    final entries = _entries;
    entries[item.key] = {
      'vote': vote(item) == value ? 0 : value,
      'at': DateTime.now().toUtc().toIso8601String(),
      'item': item.toJson(),
    };
    _all[scope] = entries;
    final snapshot = jsonEncode(_all);
    notifyListeners();
    _writes = _writes.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, snapshot);
      onSaved?.call();
    });
    return _writes;
  }

  static String merge(String local, String remote) {
    Map<String, dynamic> decode(String raw) {
      try {
        return Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {
        return {};
      }
    }

    final out = decode(local);
    for (final profile in decode(remote).entries) {
      if (profile.value is! Map) continue;
      final entries = Map<String, dynamic>.from(out[profile.key] as Map? ?? {});
      for (final e in (profile.value as Map).entries) {
        if (e.key is! String || e.value is! Map) continue;
        final incoming = e.value as Map;
        final existing = entries[e.key];
        final at = DateTime.tryParse(incoming['at']?.toString() ?? '');
        final before = existing is Map
            ? DateTime.tryParse(existing['at']?.toString() ?? '')
            : null;
        if (at != null && (before == null || at.isAfter(before))) {
          entries[e.key as String] = incoming;
        }
      }
      out[profile.key] = entries;
    }
    return jsonEncode(out);
  }
}
