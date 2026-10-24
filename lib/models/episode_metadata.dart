import '../services/image_url.dart';

/// Public episode metadata, always scoped to a series, season and episode.
class EpisodeMetadata {
  final int seriesId;
  final int season;
  final int episode;
  final String title;
  final String overview;
  final double tmdbRating;
  final String? stillPath;
  const EpisodeMetadata({
    required this.seriesId,
    required this.season,
    required this.episode,
    this.title = '',
    this.overview = '',
    this.tmdbRating = 0,
    this.stillPath,
  });
  String? get stillUrl =>
      stillPath != null &&
          RegExp(r'^/[A-Za-z0-9_]+\.(jpg|png|webp)$').hasMatch(stillPath ?? '')
      ? 'https://image.tmdb.org/t/p/w500$stillPath'
      : null;
  String get key => 'tv:$seriesId:$season:$episode';
  Map<String, dynamic> toJson() => {
    'id': seriesId,
    'season': season,
    'episode': episode,
    'title': title,
    'overview': overview,
    'rating': tmdbRating,
    'still_path': stillPath,
  };
  static EpisodeMetadata? parse(Object? raw) {
    if (raw is! Map ||
        raw['id'] is! num ||
        raw['season'] is! num ||
        raw['episode'] is! num)
      return null;
    return EpisodeMetadata(
      seriesId: (raw['id'] as num).toInt(),
      season: (raw['season'] as num).toInt(),
      episode: (raw['episode'] as num).toInt(),
      title: '${raw['title'] ?? ''}',
      overview: '${raw['overview'] ?? ''}',
      tmdbRating: (raw['rating'] as num?)?.toDouble() ?? 0,
      stillPath: raw['still_path'] is String
          ? raw['still_path'] as String
          : null,
    );
  }
}

String episodeSynopsis(
  String? official,
  String? episodePlot,
  String? seriesPlot,
) {
  for (final value in [official, episodePlot, seriesPlot]) {
    if (value != null && value.trim().isNotEmpty) return value.trim();
  }
  return '';
}

List<String> episodeArtwork(
  EpisodeMetadata? metadata,
  String? provider,
  String? series,
) => {
  for (final raw in [metadata?.stillUrl, provider, series])
    if (cleanImageUrl(raw).isNotEmpty) cleanImageUrl(raw),
}.toList();
