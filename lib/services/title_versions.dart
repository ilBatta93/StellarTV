import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';
import 'catalog_index_builder.dart' show catalogEntryKey;
import 'live_variants.dart';

/// Copies of one film in different qualities. The detail page plays the
/// version picked for that title on this device; without a pick, the one
/// already started, then Full HD before HD, standard, SD and 4K (4K copies
/// are often HEVC profiles a TV stick cannot decode).
class TitleVersions extends ChangeNotifier {
  TitleVersions._();
  static final instance = TitleVersions._();

  static const _key = 'title_version_choice_v1';

  Map<String, String> _choice = const {};
  Future<void>? _loading;

  Future<void> load() => _loading ??= () async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _choice = {for (final e in decoded.entries) '${e.key}': '${e.value}'};
        notifyListeners();
      }
    } catch (_) {}
  }();

  @visibleForTesting
  void reset() {
    _choice = const {};
    _loading = null;
  }

  /// Short quality name ("Full HD", "HD", "4K", "Standard"...).
  static String labelOf(Channel c) => parseLiveName(c.name).quality.label;

  /// Version to play among [versions] (all of one film).
  Channel pick(List<Channel> versions, {String? startedId}) {
    final chosen = _choice[catalogEntryKey(versions.first)];
    for (final id in [chosen, startedId]) {
      final hit = versions.where((c) => c.id == id).firstOrNull;
      if (hit != null) return hit;
    }
    var best = versions.first;
    var rank = parseLiveName(best.name).quality.preference;
    for (final c in versions.skip(1)) {
      final r = parseLiveName(c.name).quality.preference;
      if (r < rank) {
        best = c;
        rank = r;
      }
    }
    return best;
  }

  /// Remembers [version] as the copy to play for its title.
  Future<void> choose(Channel version) async {
    await load();
    final key = catalogEntryKey(version);
    if (_choice[key] == version.id) return;
    _choice = {..._choice, key: version.id};
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_choice));
  }
}
