/// Public episode metadata, always scoped to a series, season and episode.
class EpisodeMetadata {
  final int seriesId;
  final int season;
  final int episode;
  final String title;
  final String overview;
  final double tmdbRating;
  const EpisodeMetadata({
    required this.seriesId,
    required this.season,
    required this.episode,
    this.title = '',
    this.overview = '',
    this.tmdbRating = 0,
  });
  String get key => 'tv:$seriesId:$season:$episode';
  Map<String, dynamic> toJson() => {
    'id': seriesId,
    'season': season,
    'episode': episode,
    'title': title,
    'overview': overview,
    'rating': tmdbRating,
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
