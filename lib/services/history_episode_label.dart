import '../models/content_type.dart';

/// Presentation fallback for restored history, without mutating its identity.
String? historyEpisodeLabel({
  required ContentType type,
  int? season,
  int? episode,
  required String historyTitle,
  required String channelTitle,
}) {
  if (type != ContentType.series && type != ContentType.anime) return null;
  for (final title in [historyTitle, channelTitle]) {
    if (season != null && episode != null) break;
    final match = RegExp(
      r'\bS(\d{1,3})\s*[. _-]*E(\d{1,4})\b|\b(\d{1,3})x(\d{1,4})\b',
      caseSensitive: false,
    ).firstMatch(title);
    if (match == null) continue;
    season ??= int.tryParse(match[1] ?? match[3] ?? '');
    episode ??= int.tryParse(match[2] ?? match[4] ?? '');
  }
  if (season == null || episode == null || season < 0 || episode < 1) return null;
  return 'S$season · E$episode';
}