/// The server marks normalized payloads so weighting is applied exactly once.
double reliableTmdbVote(Object? average, Object? count) {
  if (average is! num || !average.isFinite || average <= 0 || average > 10)
    return 0;
  if (count is! num || !count.isFinite || count <= 0) return 0;
  final value = count >= 20
      ? average.toDouble()
      : (count * average + 20 * 6.0) / (count + 20);
  return (value * 10).round() / 10;
}

double tmdbPayloadVote(Map<dynamic, dynamic> data) {
  final average = data['vote_average'];
  if (data['stellar_vote_policy'] == 1 &&
      average is num &&
      average.isFinite &&
      average >= 0 &&
      average <= 10) {
    return average.toDouble();
  }
  return reliableTmdbVote(average, data['vote_count']);
}

/// Unknown IMDb is pending, not proof of absence: do not show a temporary TMDB vote.
double preferredRating(double? imdb, double tmdb) => imdb == null
    ? 0
    : imdb > 0
    ? imdb
    : tmdb;
