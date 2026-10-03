enum ContentType { live, movie, series, anime }

extension ContentTypeExtension on ContentType {
  String get label {
    switch (this) {
      case ContentType.live:
        return 'Live TV';
      case ContentType.movie:
        return 'Movies';
      case ContentType.series:
        return 'Series';
      case ContentType.anime:
        return 'Anime';
    }
  }
}
