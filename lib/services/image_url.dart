/// Provider artwork normalization, shared by the catalog downloader (isolate)
/// and series details. Kept allocation-light: it runs once per catalog item.
final RegExp _tmdbPath = RegExp(
  r'^/[A-Za-z0-9_\-/]+\.(jpg|jpeg|png|webp)$',
  caseSensitive: false,
);

/// Drops empty/"null" values, completes bare TMDB paths and
/// protocol-relative URLs, and encodes spaces.
String cleanImageUrl(Object? raw) {
  if (raw == null) return '';
  var u = raw.toString().trim();
  if (u.isEmpty || u == 'null' || u == 'false' || u == '0') return '';
  if (u.startsWith('//')) {
    u = 'https:$u';
  } else if (u.startsWith('/') && _tmdbPath.hasMatch(u)) {
    u = 'https://image.tmdb.org/t/p/w780$u';
  }
  if (!u.startsWith('http://') && !u.startsWith('https://')) return '';
  return u.contains(' ') ? u.replaceAll(' ', '%20') : u;
}

/// First usable artwork among provider fields, in priority order.
String firstImageUrl(Iterable<Object?> candidates) {
  for (final c in candidates) {
    final u = cleanImageUrl(c);
    if (u.isNotEmpty) return u;
  }
  return '';
}
