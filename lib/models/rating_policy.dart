/// The server marks normalized payloads so weighting is applied exactly once.
double reliableTmdbVote(Object? average, Object? count) {
  if (average is! num || !average.isFinite || average <= 0 || average > 10) {
    return 0;
  }
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

/// Catalog sort value for an IMDb rating. A few enthusiastic votes must
/// not put an unknown title above a classic, so ratings are pulled toward
/// an average (6.5) by 500 phantom votes, as IMDb's own charts do.
/// Unknown vote counts (scores saved before counts existed) stay as they are.
double weightedImdb(double rating, int votes) {
  if (rating <= 0 || votes <= 0) return rating;
  return (votes * rating + 500 * 6.5) / (votes + 500);
}

/// "1,2 Mln", "48 mila", "830" — Italian short form of an IMDb vote count.
String imdbVotesLabel(int votes) {
  String one(double v) {
    final s = v.toStringAsFixed(v < 10 ? 1 : 0);
    return s.endsWith('.0')
        ? s.substring(0, s.length - 2)
        : s.replaceAll('.', ',');
  }

  if (votes >= 1000000) return '${one(votes / 1000000)} Mln';
  if (votes >= 1000) return '${one(votes / 1000)} mila';
  return '$votes';
}

/// One IMDb answer kept on the device: rating (0 = IMDb has none), vote
/// count (0 = unknown) and how many days it stays fresh.
class ImdbScore {
  const ImdbScore(this.rating, {this.votes = 0, int? days})
    : days = days ?? (rating > 0 ? 30 : 3);

  final double rating;
  final int votes;
  final int days;

  Object toJson() => [rating, votes, days];

  /// Accepts the old bare number and the current `[rating, votes, days]`.
  static ImdbScore? fromJson(Object? raw) {
    if (raw is num) return ImdbScore(raw.toDouble());
    if (raw is List && raw.length == 3 && raw[0] is num) {
      return ImdbScore(
        (raw[0] as num).toDouble(),
        votes: raw[1] is num ? (raw[1] as num).toInt() : 0,
        days: raw[2] is num ? (raw[2] as num).toInt().clamp(1, 30) : null,
      );
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ImdbScore &&
      other.rating == rating &&
      other.votes == votes &&
      other.days == days;

  @override
  int get hashCode => Object.hash(rating, votes, days);
}
