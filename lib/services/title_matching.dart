/// Device-only parsing: never changes playlist, history or favorite identifiers.
class ParsedTitle {
  final String title;
  final String? year;
  const ParsedTitle(this.title, this.year);
  String key(String type) =>
      '$type:${normalizeTitle(title)}:${year ?? "unknown"}';
}

final _technical = RegExp(
  r'\s+(?:4K|UHD|FHD|HD|SD|2160P|1080P|1080I|720P|480P|HEVC|H[ -]?26[45]|X[ -]?26[45]|AVC|10BIT|8BIT|HDR10\+?|HDR|DV|DOLBY VISION|DOVI|SDR|WEB[ -]?DL|WEBRIP|WEB|BLURAY|BDRIP|BRRIP|DVDRIP|HDTV|REMUX|PROPER|REPACK|AC3|EAC3|DDP?5[ -]1|AAC|DTS(?:[ -]HD(?:[ -]MA)?)?|ATMOS|TRUEHD|5 1|7 1|SUB[ -]?ITA|SUBS?|ITA|ITALIAN|ENG|ENGLISH|MULTI|DUAL|AUDIO)\s*$',
  caseSensitive: false,
);

ParsedTitle parseTitle(String raw) {
  var t = raw.replaceAll(
    RegExp(r'\.(mkv|mp4|avi|ts|m3u8|mov|wmv)\s*$', caseSensitive: false),
    '',
  );
  t = t.replaceAll(
    RegExp(r'^\s*\[(IT|ITA|ENG|4K|UHD|HD)\]\s*', caseSensitive: false),
    '',
  );
  t = t.replaceAll(RegExp(r'^\s*(?:NETFLIX|CINEMA|FILM|TOP|PRIME|IT|ITA|ENG)\s*[|:]\s+', caseSensitive: false), '');
  t = t.replaceAll(RegExp(r'^\s*[A-Z]{2,3}\s*-\s+'), '');
  t = t.replaceAll(RegExp(r'[._]'), ' ');
  t = t.replaceAllMapped(RegExp(r'\[([^\]]*)\]|\(([^)]*)\)'), (m) {
    final inner = (m[1] ?? m[2] ?? '').trim();
    return RegExp(r'^(19|20)\d{2}$').hasMatch(inner) ||
            _technical.hasMatch(' $inner')
        ? ' $inner '
        : m[0] ?? '';
  });
  t = t.replaceAll(
    RegExp(
      r'\bS\d{1,2}\s*E\d{1,3}\b|\b\d{1,2}x\d{1,3}\b',
      caseSensitive: false,
    ),
    ' ',
  );
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  while (_technical.hasMatch(t)) {
    t = t.replaceAll(_technical, '').trim();
  }
  // A leading number may be the title itself (1917, 2001: A Space Odyssey).
  final yearMatch = RegExp(r'\s+((?:19|20)\d{2})\s*$').firstMatch(t);
  final year = yearMatch?.group(1);
  if (yearMatch != null) t = t.substring(0, yearMatch.start).trim();
  // Remove date patterns like 17/10/2026 or 17-10-2026
  t = t.replaceAll(RegExp(r'\b\d{1,2}[/_-]\d{1,2}[/_-]\d{4}\b', caseSensitive: false), '');
  t = t
      .replaceAll(RegExp(r'\s*[|]\s*'), ' ')
      .replaceAll(RegExp(r'\s+[-–:]\s*$'), '')
      .trim();
  return ParsedTitle(t, year);
}

String normalizeTitle(String title) => title
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9à-ÿ]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

List<String> titleQueries(String title) {
  final parts = title.split(RegExp(r'\s+[/–-]\s+|\s*/\s*'));
  return {
    title,
    ...parts.where((p) => p.trim().isNotEmpty).map((p) => p.trim()),
  }.toList();
}

bool matchesTitle(ParsedTitle parsed, Iterable<String> names, String year) {
  if (parsed.year != null && parsed.year != year) return false;
  final targets = titleQueries(parsed.title).map(normalizeTitle).toSet();
  return names.any((name) => targets.contains(normalizeTitle(name)));
}

/// Notable traits worth keeping in a displayed name (3D, special cuts).
final _notable = RegExp(
  r"\b(3D|EXTENDED(?: CUT| EDITION)?|DIRECTOR'?S CUT|UNCUT|UNRATED|REMASTERED|IMAX|VERSIONE ESTESA|EDIZIONE SPECIALE)\b",
  caseSensitive: false,
);

/// On-screen name: the bare title without dots, years, quality or language
/// tags. Notable traits (3D, special editions) are kept as a short suffix.
/// Display only: identifiers and matching keys never use this value.
String displayTitle(String raw) {
  if (raw.trim().isEmpty) return raw;
  final dotted = raw
      .replaceAll(
        RegExp(r'\.(mkv|mp4|avi|ts|m3u8|mov|wmv)\s*$', caseSensitive: false),
        '',
      )
      .replaceAllMapped(
    RegExp(r'(?<=[A-Za-zÀ-ÿ0-9])[._](?=[A-Za-zÀ-ÿ0-9(\[])'),
    (_) => ' ',
  );
  final traits = <String>[];
  for (final m in _notable.allMatches(dotted)) {
    final v = m.group(1)!.toUpperCase() == '3D'
        ? '3D'
        : m.group(1)!
              .toLowerCase()
              .split(' ')
              .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
              .join(' ');
    if (!traits.contains(v)) traits.add(v);
  }
  var parsed = parseTitle(dotted.replaceAll(_notable, ' '));
  var t = parsed.title;
  final year = parsed.year;

  // Check if original raw had year in parentheses like (YYYY) or after a dot like .YYYY
  final hasYearInParens = RegExp(r'\(\d{4}\)\s*$').hasMatch(raw.trim());
  final hasDotYear = RegExp(r'\.\d{4}\s*$').hasMatch(raw.trim());

  if (year != null) {
    // If year was in parentheses or after a dot, do NOT add it back (e.g. Cave.Diving.(2024) -> Cave Diving)
    if (hasYearInParens || hasDotYear) {
      // suppress: year already stripped by parseTitle, don't re-add
    } else if (!t.endsWith(' $year')) {
      // Year trailing without parentheses, keep it (e.g. Blade Runner 2049)
      t = '$t $year';
    }
  }
  t = t
      .replaceAll(RegExp(r'[\[\]()]\s*[\[\]()]'), ' ')
      .replaceAll(RegExp(r'\s*[-–:|]\s*$'), '')
      .replaceAll(RegExp(r'^\s*[-–:|]\s*'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (t.isEmpty) return raw.trim();
  return traits.isEmpty ? t : '$t (${traits.join(', ')})';
}

/// Audiobook entries get a dedicated cover when the provider has none.
bool isAudiobook(String name, String group) =>
    RegExp(r'audio ?libr|audiobook', caseSensitive: false)
        .hasMatch('$group $name');
