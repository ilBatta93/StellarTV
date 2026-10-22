import 'introdb_service.dart';

/// Bounded title cleanup, leaving names, years and catalog identifiers intact.
String segmentLookupTitle(String title) => title
    .replaceFirst(
      RegExp(
        r'^\s*(?:IT|ITA|EN|UK|US|FR|DE|ES)\s*[:|]\s*',
        caseSensitive: false,
      ),
      '',
    )
    .replaceAll(
      RegExp(
        r'\b(?:S\d{1,2}\s*E\d{1,3}|\d{1,2}x\d{1,3})\b',
        caseSensitive: false,
      ),
      ' ',
    )
    .replaceAll(
      RegExp(
        r'\b(?:4K|UHD|FHD|HD|SD|720p|1080p|2160p|H[ .]?26[45]|X26[45]|HEVC|WEB[ .-]?DL|WEBRIP|BLURAY|HDR10?|DV)\b',
        caseSensitive: false,
      ),
      ' ',
    )
    .replaceAll(RegExp(r'\[\s*\]|\(\s*\)'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

EpisodeSegments validSegments(EpisodeSegments source, Duration duration) {
  if (duration <= Duration.zero) return EpisodeSegments.empty;
  bool valid(SkipSegment? s) =>
      s != null &&
      s.start >= Duration.zero &&
      s.end > s.start &&
      s.end <= duration;
  return EpisodeSegments(
    intro: valid(source.intro) ? source.intro : null,
    outro: valid(source.outro) ? source.outro : null,
    all: source.all.where((s) => valid(s)).toList(growable: false),
  );
}

EpisodeSegments chapterSegments(
  List<Map<String, Object?>> chapters,
  Duration duration,
) {
  if (duration <= Duration.zero || chapters.length > 40)
    return EpisodeSegments.empty;
  final all = <SkipSegment>[];
  for (var i = 0; i < chapters.length; i++) {
    final c = chapters[i];
    final name = '${c['title'] ?? ''}'.trim().toLowerCase();
    final type = switch (name) {
      'intro' || 'introduction' || 'opening' || 'sigla' => 'intro',
      'credits' ||
      'end credits' ||
      'ending' ||
      'outro' ||
      'titoli di coda' => 'outro',
      _ => '',
    };
    final start = c['time'];
    final end = i + 1 < chapters.length
        ? chapters[i + 1]['time']
        : duration.inMilliseconds / 1000;
    if (type.isEmpty ||
        start is! num ||
        end is! num ||
        !start.isFinite ||
        !end.isFinite ||
        start < 0 ||
        end <= start)
      continue;
    // Avoid generic opening/ending labels swallowing the whole programme.
    if (type == 'intro' && end - start > 240 ||
        type == 'outro' && start < duration.inSeconds / 2)
      continue;
    all.add(
      SkipSegment(
        type,
        Duration(milliseconds: (start * 1000).round()),
        Duration(milliseconds: (end * 1000).round()),
      ),
    );
  }
  return validSegments(
    EpisodeSegments(
      intro: all.where((s) => s.type == 'intro').firstOrNull,
      outro: all.where((s) => s.type == 'outro').firstOrNull,
      all: all,
    ),
    duration,
  );
}

bool suggestNext({required Duration position, required Duration duration}) =>
    duration >= const Duration(minutes: 5) &&
    position >= duration - const Duration(seconds: 90) &&
    position <= duration;
