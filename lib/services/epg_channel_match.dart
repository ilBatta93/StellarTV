/// Pure guide-matching rules shared by the EPG provider and tests.
///
/// A playlist channel is matched only to a guide channel with the same
/// timeshift ("+1", "+2"): a shared tvg-id never gives "Canale 5 +1" the
/// programmes of "Canale 5". When the guide has no dedicated timeshift
/// channel, the base channel is used with every programme moved forward by
/// the timeshift hours.
class EpgMatch {
  final String id;
  final int shiftHours;
  const EpgMatch(this.id, this.shiftHours);
  @override
  bool operator ==(Object other) =>
      other is EpgMatch && other.id == id && other.shiftHours == shiftHours;
  @override
  int get hashCode => Object.hash(id, shiftHours);
  @override
  String toString() => 'EpgMatch($id, +$shiftHours)';
}

/// Separator between multiple XMLTV display-names of one channel.
const epgNameSeparator = '\u0001';

final _shiftRe = RegExp(
  r'(?:\+\s*([1-9])\s*(?:h\b)?|\bplus\s*([1-9])\b|\b([1-9])\s*h\b)',
  caseSensitive: false,
);

/// Timeshift hours named in a channel name or guide id (0 = live channel).
int epgShiftOf(String text) {
  final m = _shiftRe.firstMatch(text);
  if (m == null) return 0;
  return int.parse(m.group(1) ?? m.group(2) ?? m.group(3)!);
}

/// Name key without timeshift marks, prefixes and quality tags.
String epgBaseKey(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'^\s*[a-z]{2,3}\s*[:|\-]\s*'), '')
    .replaceAll(RegExp(r'\.(it|uk|de|fr|es|us|com)$'), '')
    .replaceAll(_shiftRe, ' ')
    .replaceAll(RegExp(r'\b(fhd|uhd|hd|sd|4k|hevc|h265|backup|ita|italia)\b'), ' ')
    .replaceAll(RegExp(r'[^a-z0-9]+'), '');

class EpgMatcher {
  final Set<String> guideIds;
  final Map<String, String> displayNames;
  EpgMatcher({required this.guideIds, required this.displayNames}) {
    _build();
  }

  final Map<String, int> _guideShift = {};
  // (base key, shift) -> guide id; ambiguous keys are dropped.
  final Map<String, String> _byName = {};
  final Set<String> _ambiguous = {};
  final Map<String, String> _lowerIds = {};

  List<String> _namesOf(String id) => [
    id,
    ...(displayNames[id] ?? '').split(epgNameSeparator).where((n) => n.trim().isNotEmpty),
  ];

  void _build() {
    for (final id in guideIds) {
      _lowerIds[id.toLowerCase()] = id;
      var shift = 0;
      for (final n in _namesOf(id)) {
        final s = epgShiftOf(n);
        if (s > shift) shift = s;
      }
      _guideShift[id] = shift;
      for (final n in _namesOf(id)) {
        final key = '${epgBaseKey(n)}#$shift';
        if (key.startsWith('#') || _ambiguous.contains(key)) continue;
        final prior = _byName[key];
        if (prior == null) {
          _byName[key] = id;
        } else if (prior != id) {
          _byName.remove(key);
          _ambiguous.add(key);
        }
      }
    }
  }

  String? _byTvg(String? tvg) {
    final t = tvg?.trim();
    if (t == null || t.isEmpty) return null;
    return guideIds.contains(t) ? t : _lowerIds[t.toLowerCase()];
  }

  String? _byNameKey(Iterable<String> names, int shift) {
    for (final n in names) {
      final id = _byName['${epgBaseKey(n)}#$shift'];
      if (id != null) return id;
    }
    return null;
  }

  EpgMatch? match({required String name, String? tvgName, String? tvgId}) {
    final names = [name, if (tvgName != null && tvgName.trim().isNotEmpty) tvgName];
    // The visible channel name decides the timeshift: providers often copy
    // the base tvg-id/tvg-name onto the "+1" channel.
    var shift = 0;
    for (final n in names) {
      final s = epgShiftOf(n);
      if (s > shift) shift = s;
    }
    final tvg = _byTvg(tvgId);
    if (tvg != null && _guideShift[tvg] == shift) return EpgMatch(tvg, 0);
    final exact = _byNameKey(names, shift);
    if (exact != null) return EpgMatch(exact, 0);
    if (shift == 0) return null;
    // No dedicated timeshift guide: base channel moved forward.
    final base = (tvg != null && _guideShift[tvg] == 0) ? tvg : _byNameKey(names, 0);
    return base == null ? null : EpgMatch(base, shift);
  }
}
