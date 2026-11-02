enum ContentType { live, movie, series, anime }

extension ContentTypeExtension on ContentType {
  String get label {
    switch (this) {
      case ContentType.live:
        return 'Diretta';
      case ContentType.movie:
        return 'Film';
      // Animation is a classification inside the Serie TV section, not a
      // section of its own.
      case ContentType.series:
      case ContentType.anime:
        return 'Serie TV';
    }
  }
}
