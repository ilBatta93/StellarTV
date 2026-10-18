enum ContentType { live, movie, series, anime }

extension ContentTypeExtension on ContentType {
  String get label {
    switch (this) {
      case ContentType.live:
        return 'Diretta';
      case ContentType.movie:
        return 'Film';
      case ContentType.series:
        return 'Serie TV';
      case ContentType.anime:
        return 'Anime';
    }
  }
}
