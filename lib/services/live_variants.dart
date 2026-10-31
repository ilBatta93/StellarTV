import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Copies of one live channel that only differ by quality ("Rai 1",
/// "Rai 1 HD", "Rai 1 FHD", "Rai 1 4K"): the TV guide and zapping show them
/// as one channel, and the viewer picks the version from a short list.
///
/// The default version is Full HD, then HD: 4K/UHD copies are often HEVC
/// profiles a TV stick cannot decode (sound only). A version the viewer
/// picks is remembered per channel on this device.
class LiveVariants extends ChangeNotifier {
  LiveVariants._();
  static final instance = LiveVariants._();

  static const _choiceKey = 'live_variant_choice_v1';

  Map<String, String> _keyOf = const {};
  Map<String, List<String>> _members = const {};
  Map<String, int> _order = const {};
  Map<String, String> _labelOf = const {};
  Map<String, String> _choice = const {};
  int? _boundRevision;
  int? _bindingRevision;
  Future<void>? _choiceLoad;
  int _revision = 0;

  /// Changes whenever groups or remembered choices change.
  int get revision => _revision;

  bool get hasGroups => _members.isNotEmpty;

  /// Builds the groups once per catalog revision, off the UI isolate.
  Future<void> bind(
    int catalogRevision,
    Future<List<Map<String, String>>> Function() identities,
  ) async {
    if (_boundRevision == catalogRevision ||
        _bindingRevision == catalogRevision) {
      return;
    }
    _bindingRevision = catalogRevision;
    try {
      await (_choiceLoad ??= _loadChoices());
      final rows = await identities();
      if (_bindingRevision != catalogRevision) return;
      final pairs = [
        for (final row in rows)
          if ((row['id'] ?? '').isNotEmpty)
            (id: row['id']!, name: row['name'] ?? ''),
      ];
      final index = pairs.isEmpty
          ? LiveVariantIndex.empty
          : await Isolate.run(() => LiveVariantIndex.build(pairs));
      if (_bindingRevision != catalogRevision) return;
      apply(index);
      _boundRevision = catalogRevision;
    } catch (_) {
      // Grouping is a convenience: the guide stays ungrouped.
    } finally {
      if (_bindingRevision == catalogRevision) _bindingRevision = null;
    }
  }

  @visibleForTesting
  void apply(LiveVariantIndex index) {
    _keyOf = index.keyOf;
    _members = index.members;
    _order = index.order;
    _labelOf = index.labels;
    _revision++;
    notifyListeners();
  }

  @visibleForTesting
  void reset() {
    _keyOf = const {};
    _members = const {};
    _order = const {};
    _labelOf = const {};
    _choice = const {};
    _boundRevision = null;
    _bindingRevision = null;
    _choiceLoad = null;
    _revision++;
  }

  Future<void> _loadChoices() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_choiceKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _choice = {for (final e in decoded.entries) '${e.key}': '${e.value}'};
      }
    } catch (_) {}
  }

  /// Every version of the channel [id], itself included, in playlist order.
  List<String> idsOf(String id) {
    final key = _keyOf[id];
    return key == null ? [id] : _members[key]!;
  }

  /// Short quality name of [id] ("Full HD", "HD", "4K"...) when it has
  /// other versions.
  String? labelOf(String id) => _keyOf.containsKey(id) ? _labelOf[id] : null;

  /// Version to play among [candidates] (all of one channel).
  String pick(List<String> candidates) {
    if (candidates.isEmpty) throw ArgumentError('nessuna versione');
    final key = _keyOf[candidates.first];
    final chosen = key == null ? null : _choice[key];
    if (chosen != null && candidates.contains(chosen)) return chosen;
    var best = candidates.first;
    for (final id in candidates.skip(1)) {
      if ((_order[id] ?? 9) < (_order[best] ?? 9)) best = id;
    }
    return best;
  }

  /// Remembers [id] as the version to play for its channel.
  Future<void> choose(String id) async {
    final key = _keyOf[id];
    if (key == null || _choice[key] == id) return;
    await (_choiceLoad ??= _loadChoices());
    _choice = {..._choice, key: id};
    _revision++;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_choiceKey, jsonEncode(_choice));
  }

  /// One id per channel, at the position of its first version. [keep]
  /// stays as its channel's version (the one playing).
  List<String> collapse(List<String> ids, {String? keep}) {
    if (_members.isEmpty) return ids;
    final out = <String>[];
    final slotOf = <String, int>{};
    final present = <String, List<String>>{};
    for (final id in ids) {
      final key = _keyOf[id];
      if (key == null) {
        out.add(id);
        continue;
      }
      final versions = present[key];
      if (versions == null) {
        slotOf[key] = out.length;
        present[key] = [id];
        out.add(id);
      } else {
        versions.add(id);
      }
    }
    if (out.length == ids.length) return ids;
    for (final entry in present.entries) {
      final versions = entry.value;
      if (versions.length < 2) continue;
      out[slotOf[entry.key]!] = keep != null && versions.contains(keep)
          ? keep
          : pick(versions);
    }
    return out;
  }
}

/// Groups computed from channel names; only channels with two or more
/// versions are kept.
class LiveVariantIndex {
  const LiveVariantIndex({
    required this.keyOf,
    required this.members,
    required this.order,
    required this.labels,
  });

  static const empty = LiveVariantIndex(
    keyOf: {},
    members: {},
    order: {},
    labels: {},
  );

  final Map<String, String> keyOf;
  final Map<String, List<String>> members;
  final Map<String, int> order;
  final Map<String, String> labels;

  static LiveVariantIndex build(List<({String id, String name})> channels) {
    final byKey = <String, List<String>>{};
    final quality = <String, LiveQuality>{};
    for (final c in channels) {
      final parsed = parseLiveName(c.name);
      if (parsed.key.isEmpty) continue;
      final ids = byKey[parsed.key] ??= <String>[];
      if (ids.contains(c.id)) continue;
      ids.add(c.id);
      quality[c.id] = parsed.quality;
    }
    final keyOf = <String, String>{};
    final members = <String, List<String>>{};
    final order = <String, int>{};
    final labels = <String, String>{};
    for (final entry in byKey.entries) {
      if (entry.value.length < 2) continue;
      members[entry.key] = List.unmodifiable(entry.value);
      for (final id in entry.value) {
        keyOf[id] = entry.key;
        order[id] = quality[id]!.preference;
        labels[id] = quality[id]!.label;
      }
    }
    return LiveVariantIndex(
      keyOf: keyOf,
      members: members,
      order: order,
      labels: labels,
    );
  }
}

enum LiveQuality {
  fullHd('Full HD', 0),
  hd('HD', 1),
  standard('Standard', 2),
  hevc('HEVC', 3),
  sd('SD', 4),
  uhd('4K', 5);

  const LiveQuality(this.label, this.preference);
  final String label;

  /// Lower plays first when nothing was picked yet.
  final int preference;
}

final _liveSplit = RegExp(r'[^a-z0-9à-ÿ+]+');
final _fullHd = RegExp(r'full\s*hd');
final _ultraHd = RegExp(r'ultra\s*hd');
const _superscripts = {
  'ᵁᴴᴰ': ' uhd ',
  'ᶠᴴᴰ': ' fhd ',
  'ᴴᴰ': ' hd ',
  'ˢᴰ': ' sd ',
  '⁴ᴷ': ' 4k ',
};

/// Channel name without its quality words, plus the quality they name.
/// "+1" and numbers stay: "Rai 1", "Rai 2" and "Canale 5 +1" are different
/// channels.
({String key, LiveQuality quality}) parseLiveName(String name) {
  var text = name;
  for (final e in _superscripts.entries) {
    text = text.replaceAll(e.key, e.value);
  }
  text = text
      .toLowerCase()
      .replaceAll(_fullHd, ' fhd ')
      .replaceAll(_ultraHd, ' uhd ');
  LiveQuality? resolution;
  var codec = false;
  final words = <String>[];
  for (final word in text.split(_liveSplit)) {
    if (word.isEmpty) continue;
    final q = _qualityWord(word);
    if (q == null) {
      words.add(word);
    } else if (q == LiveQuality.hevc) {
      codec = true;
    } else if (q != _codecOnly) {
      resolution ??= q;
    }
  }
  return (
    key: words.join(' '),
    quality: resolution ?? (codec ? LiveQuality.hevc : LiveQuality.standard),
  );
}

/// Marker for words that are dropped without naming a quality.
const _codecOnly = LiveQuality.standard;

LiveQuality? _qualityWord(String word) => switch (word) {
  '4k' || 'uhd' || 'ufhd' || '2160' || '2160p' => LiveQuality.uhd,
  'fhd' || '1080' || '1080p' || '1080i' => LiveQuality.fullHd,
  'hd' || '720' || '720p' => LiveQuality.hd,
  'sd' || '576' || '576p' || '480' || '480p' => LiveQuality.sd,
  'hevc' || 'h265' || 'x265' => LiveQuality.hevc,
  'h264' || 'x264' || '50fps' || '60fps' || 'hdr' => _codecOnly,
  _ => null,
};
