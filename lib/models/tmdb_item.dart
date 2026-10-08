import 'content_type.dart';

class TmdbItem {
  final int id;
  final String mediaType;
  final String title;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final double voteAverage;
  final double popularity;
  final String releaseDate;

  const TmdbItem({
    required this.id,
    required this.mediaType,
    required this.title,
    required this.overview,
    required this.posterPath,
    required this.backdropPath,
    required this.voteAverage,
    required this.popularity,
    required this.releaseDate,
  });

  bool get isMovie => mediaType == 'movie';
  String get key => '${mediaType}_$id';
  ContentType get contentType => isMovie ? ContentType.movie : ContentType.series;
  String get year => releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';

  String? get posterUrl =>
      posterPath == null ? null : 'https://image.tmdb.org/t/p/w500$posterPath';
  String? get backdropUrl => backdropPath == null
      ? posterUrl
      : 'https://image.tmdb.org/t/p/w1280$backdropPath';

  static TmdbItem? tryParse(Map<String, dynamic> json, {String? fallbackType}) {
    final type = json['media_type'] as String? ?? fallbackType;
    final id = json['id'];
    if (id is! int || (type != 'movie' && type != 'tv')) return null;
    final title = (json['title'] ?? json['name'] ?? '').toString();
    if (title.isEmpty) return null;
    return TmdbItem(
      id: id,
      mediaType: type!,
      title: title,
      overview: (json['overview'] ?? '').toString(),
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0,
      popularity: (json['popularity'] as num?)?.toDouble() ?? 0,
      releaseDate:
          (json['release_date'] ?? json['first_air_date'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'media_type': mediaType,
        'title': title,
        'overview': overview,
        'poster_path': posterPath,
        'backdrop_path': backdropPath,
        'vote_average': voteAverage,
        'popularity': popularity,
        'release_date': releaseDate,
      };
}
