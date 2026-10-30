class TitleTrailer {
  const TitleTrailer({required this.key, required this.language});
  final String key;
  final String language;

  /// Non-Italian audio: the player turns on Italian subtitles.
  bool get italianSubtitles => language != 'it';
  String get badge => italianSubtitles ? 'SUB ITA' : 'ITA';
  Uri get url => Uri.https('www.youtube.com', '/watch', {'v': key});

  /// Trailer first, then Teaser; official before fan uploads; newest first.
  static int _typeRank(Object? type) => switch (type) {
    'Trailer' => 0,
    'Teaser' => 1,
    _ => 9,
  };

  static TitleTrailer? select(Map<String, dynamic> body, String language) {
    final results = body['results'];
    if (results is! List) return null;
    final videos = results
        .whereType<Map<String, dynamic>>()
        .where(
          (v) =>
              v['site'] == 'YouTube' &&
              _typeRank(v['type']) < 9 &&
              v['iso_639_1'] == language &&
              v['key'] is String &&
              RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(v['key'] as String),
        )
        .toList();
    videos.sort((a, b) {
      final type = _typeRank(a['type']).compareTo(_typeRank(b['type']));
      if (type != 0) return type;
      final official = (b['official'] == true ? 1 : 0).compareTo(
        a['official'] == true ? 1 : 0,
      );
      if (official != 0) return official;
      return '${b['published_at'] ?? ''}'.compareTo(
        '${a['published_at'] ?? ''}',
      );
    });
    if (videos.isEmpty) return null;
    return TitleTrailer(key: videos.first['key'] as String, language: language);
  }
}
