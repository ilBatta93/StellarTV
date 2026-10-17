class TitleTrailer {
  const TitleTrailer({required this.key, required this.language});
  final String key;
  final String language;
  Uri get url => Uri.https('www.youtube.com', '/watch', {'v': key});

  static TitleTrailer? select(Map<String, dynamic> body, String language) {
    final results = body['results'];
    if (results is! List) return null;
    final videos = results
        .whereType<Map<String, dynamic>>()
        .where(
          (v) =>
              v['site'] == 'YouTube' &&
              v['type'] == 'Trailer' &&
              v['iso_639_1'] == language &&
              v['key'] is String &&
              RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(v['key'] as String),
        )
        .toList();
    videos.sort(
      (a, b) => (b['official'] == true ? 1 : 0).compareTo(
        a['official'] == true ? 1 : 0,
      ),
    );
    if (videos.isEmpty) return null;
    return TitleTrailer(key: videos.first['key'] as String, language: language);
  }
}
