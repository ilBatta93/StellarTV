import 'introdb_service.dart';

/// Chapter titles are free text. Match the words used on real files.
String? chapterSkipType(String raw) {
  final name = raw.trim().toLowerCase();
  if (name.isEmpty || name.length > 80) return null;
  if (RegExp(r'^(op|ncop)$').hasMatch(name)) return 'intro';
  if (RegExp(r'^(ed|nced)$').hasMatch(name)) return 'outro';
  if (RegExp(
    r'post[\s-]?credits?|after credits|scena dopo i titoli',
  ).hasMatch(name))
    return 'post_credits';
  if (RegExp(
    r'\b(recap|previously|riepilogo|negli episodi precedenti)\b',
  ).hasMatch(name))
    return 'recap';
  final intro = RegExp(
    r'\b(intro|introduction|opening|sigla|titoli di testa|theme song)\b',
  ).hasMatch(name);
  final closing = RegExp(
    r'\b(end|ending|closing|coda|chiusura)\b',
  ).hasMatch(name);
  if (intro && !closing) return 'intro';
  if (RegExp(
    r'\b(end credits|ending|outro|closing|titoli di coda|titoli di chiusura|credits)\b',
  ).hasMatch(name))
    return 'outro';
  return null;
}

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

/// Intro and recap can appear before the runtime is known. Credits wait
/// for a duration, and a small overrun is pulled back to the end of the file.
SkipSegment? fitSegment(SkipSegment s, Duration duration) {
  if (s.start < Duration.zero || s.end <= s.start) return null;
  final tail =
      s.type == 'outro' || s.type == 'credits' || s.type == 'post_credits';
  if (duration <= Duration.zero) {
    if (tail || s.start > const Duration(minutes: 15)) return null;
    if (s.end - s.start > const Duration(minutes: 8)) return null;
    return s;
  }
  if (s.start >= duration) return null;
  if (s.end <= duration) return s;
  final overshoot = s.end - duration;
  final halfway = Duration(microseconds: duration.inMicroseconds ~/ 2);
  if (overshoot <= const Duration(seconds: 20) || (tail && s.start >= halfway)) {
    return SkipSegment(s.type, s.start, duration);
  }
  return null;
}

EpisodeSegments validSegments(EpisodeSegments source, Duration duration) {
  final seen = <SkipSegment>[
    ...source.all,
    if (source.intro != null) source.intro!,
    if (source.outro != null) source.outro!,
  ];
  final all = <SkipSegment>[];
  for (final s in seen) {
    final fitted = fitSegment(s, duration);
    if (fitted == null) continue;
    final duplicate = all.any(
      (other) => other.type == fitted.type && other.start == fitted.start,
    );
    if (!duplicate) all.add(fitted);
  }
  SkipSegment? first(Set<String> types) =>
      all.where((s) => types.contains(s.type)).firstOrNull;
  return EpisodeSegments(
    intro: first({'intro'}),
    outro: first({'outro', 'credits'}),
    all: all,
  );
}

/// Chapters of this file win for the same kind of segment. Remote times fill
/// whatever the file does not label.
EpisodeSegments mergeSkipSegments(
  EpisodeSegments remote,
  EpisodeSegments local,
) {
  SkipSegment? take(String type) =>
      local.all.where((s) => s.type == type).firstOrNull ??
      remote.all.where((s) => s.type == type).firstOrNull;
  final all = <SkipSegment>[
    for (final type in ['recap', 'intro', 'outro', 'post_credits', 'credits'])
      if (take(type) case final segment?) segment,
  ];
  return EpisodeSegments(
    intro: take('intro'),
    outro: take('outro') ?? take('credits'),
    all: all,
  );
}

class SkipChoice {
  final SkipSegment segment;
  final Duration target;
  final String label;
  const SkipChoice(this.segment, this.target, this.label);
}

/// The opening segment under [position]. A recap glued to the intro skips
/// both, in one press.
SkipChoice? activeSkip(EpisodeSegments segments, Duration position) {
  final skips =
      segments.all
          .where((s) => s.type == 'intro' || s.type == 'recap')
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  SkipSegment? current;
  for (final s in skips) {
    if (s.contains(position)) current = s;
  }
  if (current == null) return null;
  var target = current.end;
  var reachesIntro = current.type == 'intro';
  for (var guard = 0; guard < 4; guard++) {
    SkipSegment? next;
    for (final s in skips) {
      if (s.start >= target && s.start - target <= const Duration(seconds: 2)) {
        next = s;
        break;
      }
    }
    if (next == null) break;
    if (next.type == 'intro') reachesIntro = true;
    target = next.end;
  }
  return SkipChoice(
    current,
    target,
    reachesIntro ? 'Salta sigla' : 'Salta riepilogo',
  );
}

/// Movies and a last episode: jump to the scene after the credits.
SkipChoice? postCreditsSkip(EpisodeSegments segments, Duration position) {
  final outro = segments.outro;
  final scene = segments.all
      .where((s) => s.type == 'post_credits')
      .firstOrNull;
  if (outro == null ||
      scene == null ||
      scene.start <= outro.start ||
      position < outro.start ||
      position >= scene.start) {
    return null;
  }
  return SkipChoice(outro, scene.start, 'Salta titoli');
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
    final type = chapterSkipType('${c['title'] ?? ''}');
    final start = c['time'];
    final end = i + 1 < chapters.length
        ? chapters[i + 1]['time']
        : duration.inMilliseconds / 1000;
    if (type == null ||
        start is! num ||
        end is! num ||
        !start.isFinite ||
        !end.isFinite ||
        start < 0 ||
        end <= start)
      continue;
    // Avoid generic opening/ending labels swallowing the whole programme.
    if ((type == 'intro' || type == 'recap') &&
            end - start > (type == 'recap' ? 480 : 240) ||
        (type == 'outro' || type == 'post_credits') &&
            start < duration.inSeconds / 2)
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
