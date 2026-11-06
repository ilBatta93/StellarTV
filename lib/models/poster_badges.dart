import 'rating_policy.dart';

/// Which score a poster shows.
enum RatingSource {
  /// IMDb, or TMDB once IMDb has confirmed it has none.
  auto,
  imdb,
  tmdb;

  String get label => switch (this) {
    RatingSource.auto => 'Automatico',
    RatingSource.imdb => 'Solo IMDb',
    RatingSource.tmdb => 'Solo TMDB',
  };

  String get description => switch (this) {
    RatingSource.auto => 'IMDb, e TMDB quando IMDb non ha un voto',
    RatingSource.imdb => 'Nessun voto se IMDb non ne ha uno',
    RatingSource.tmdb => 'Il voto della comunità TMDB',
  };

  static RatingSource parse(Object? raw) =>
      RatingSource.values.asNameMap()[raw] ?? RatingSource.auto;
}

/// Score for [source]: `imdb` null means IMDb has not answered yet.
/// Returns 0 when nothing should be shown, and whether it is the IMDb one.
({double value, bool imdb}) ratingFor(
  RatingSource source,
  double? imdb,
  double tmdb,
) {
  switch (source) {
    case RatingSource.auto:
      final value = preferredRating(imdb, tmdb);
      return (value: value, imdb: imdb != null && imdb > 0);
    case RatingSource.imdb:
      final value = imdb != null && imdb > 0 ? imdb : 0.0;
      return (value: value, imdb: true);
    case RatingSource.tmdb:
      return (value: tmdb > 0 ? tmdb : 0.0, imdb: false);
  }
}

/// Days a title added by the source keeps the «Nuovo» badge.
const newBadgeDays = 14;

/// Added by the source in the last [newBadgeDays]. Dates in the future
/// (wrong clocks on the source) do not count.
bool isRecentlyAdded(int addedAtSeconds, DateTime now) {
  if (addedAtSeconds <= 0) return false;
  final added = DateTime.fromMillisecondsSinceEpoch(addedAtSeconds * 1000);
  final age = now.difference(added);
  return !age.isNegative && age.inDays < newBadgeDays;
}

/// Where catalog titles are written.
enum TitlePlacement {
  below,
  overlay,
  hidden;

  String get label => switch (this) {
    TitlePlacement.below => 'Sotto la locandina',
    TitlePlacement.overlay => 'Sulla locandina',
    TitlePlacement.hidden => 'Nascosti',
  };

  String get description => switch (this) {
    TitlePlacement.below => 'Il titolo in una riga sotto la copertina',
    TitlePlacement.overlay => 'Su una sfumatura scura in fondo alla copertina',
    TitlePlacement.hidden => 'Un muro di sole copertine',
  };
}

/// Fixed places of everything drawn on a catalog poster, so badges never
/// cover each other:
/// - top left: the score, then «Nuovo» under it;
/// - top right: the heart;
/// - bottom left: quality, then the streaming platform;
/// - bottom right: the watched mark;
/// - bottom edge: the progress bar.
/// With titles on the poster, the bottom badges sit right above the title.
enum PosterSlot { topLeft, topRight, bottomLeft, bottomRight }
