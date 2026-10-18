enum ContentType { live, movie, series, anime }

extension ContentTypeExtension on ContentType {
  String get label {
    switch (this) {
      case ContentType.live:
        return 'Diretta';
      case ContentType.movie:
        return 'Video';
      case ContentType.series:
        return 'Raccolte';
      case ContentType.anime:
        return 'Anime';
    }
  }
}
