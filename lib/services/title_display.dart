/// Presentation only: never use this value as a stream/history identifier.
String displayTitle(String raw) {
  var title = raw.trim();
  title = title.replaceFirst(
    RegExp(r'^\s*(?:IT|ITA|EN|ENG|FR|DE|ES)\s*[:|]\s*', caseSensitive: false),
    '',
  );
  // Only metadata brackets are removed; real subtitles in parentheses survive.
  final metadata = RegExp(
    r'^(?:(?:19|20)\d{2}|\d{1,2}[/.-]\d{1,2}[/.-](?:\d{2}|\d{4})|4K|UHD|FHD|HD|SD|HEVC|H\.?26[45]|1080[pi]|720p|2160p|MULTI|ITA|ENG|SUB(?: ITA)?|DUBBED|WEB[- ]?DL|BLU[- ]?RAY|REMASTERED)(?:\s*[,| /-]\s*(?:4K|UHD|FHD|HD|SD|HEVC|ITA|ENG|MULTI))*$',
    caseSensitive: false,
  );
  title = title.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]|\(([^)]*)\)'),
    (m) => metadata.hasMatch((m[1] ?? m[2] ?? '').trim()) ? ' ' : m[0] ?? '',
  );
  title = title.replaceAll(
    RegExp(
      r'\b(?:4K|UHD|FHD|HEVC|H\.?26[45]|1080[pi]|720p|2160p|WEB[- ]?DL|BLU[- ]?RAY)\b',
      caseSensitive: false,
    ),
    ' ',
  );
  title = title.replaceAll(
    RegExp(r'\s+(?:HD|SD|MULTI|ITA|ENG|SUB ITA)\s*$', caseSensitive: false),
    '',
  );
  title = title.replaceAll(RegExp(r'\s*[-|·]\s*(?:19|20)\d{2}\s*$'), '');

  title = title.replaceAll(
    RegExp(r'\s+\d{1,2}[/.-]\d{1,2}[/.-](?:\d{4}|\d{2})\s*$'),
    '',
  );
  title = title
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s|·-]+|[\s|·-]+$'), '')
      .trim();
  return title.isEmpty ? raw.trim() : title;
}
