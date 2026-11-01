import 'tmdb_person.dart';

/// Who made a title: directors (crew), creators (series) and cast, parsed
/// from TMDB `credits` and details payloads.
class TitleCredits {
  final List<TmdbPerson> directors;
  final List<TmdbPerson> cast;

  const TitleCredits({this.directors = const [], this.cast = const []});

  static const empty = TitleCredits();

  static TitleCredits parse(Map<String, dynamic> body) {
    final seen = <int>{};
    final directors = <TmdbPerson>[
      for (final raw in (body['crew'] as List?) ?? const [])
        if (raw is Map<String, dynamic> && raw['job'] == 'Director')
          if (TmdbPerson.tryParse(raw) case final person?
              when seen.add(person.id))
            person.withRole('Regia'),
    ];
    return TitleCredits(
      directors: directors,
      cast: [
        for (final raw in (body['cast'] as List?) ?? const [])
          if (raw is Map<String, dynamic>) ?TmdbPerson.tryParse(raw),
      ],
    );
  }
}

/// Extra facts from the TMDB details of one title.
class TitleInfo {
  /// Film length in minutes, or the usual episode length for a series.
  final int? runtime;
  final String? tagline;
  final String? originalTitle;

  /// Series creators ("Ideata da").
  final List<TmdbPerson> creators;

  const TitleInfo({
    this.runtime,
    this.tagline,
    this.originalTitle,
    this.creators = const [],
  });

  static const empty = TitleInfo();

  static TitleInfo parse(Map<String, dynamic> body) {
    String? text(Object? value) {
      final s = (value ?? '').toString().trim();
      return s.isEmpty ? null : s;
    }

    int? runtime = (body['runtime'] as num?)?.toInt();
    final episodes = body['episode_run_time'];
    if (runtime == null && episodes is List && episodes.isNotEmpty) {
      runtime = (episodes.first as num?)?.toInt();
    }
    final title = text(body['title'] ?? body['name']);
    final original = text(body['original_title'] ?? body['original_name']);
    return TitleInfo(
      runtime: runtime != null && runtime > 0 ? runtime : null,
      tagline: text(body['tagline']),
      originalTitle: original != null && original != title ? original : null,
      creators: [
        for (final raw in (body['created_by'] as List?) ?? const [])
          if (raw is Map<String, dynamic>)
            if (TmdbPerson.tryParse(raw) case final person?)
              person.withRole('Ideazione'),
      ],
    );
  }
}

/// "1 h 47 min", "52 min".
String formatRuntime(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// "Mario Rossi", "Mario Rossi e Anna Bianchi", "A, B e C".
String joinNames(List<TmdbPerson> people, {int max = 3}) {
  final names = [for (final p in people.take(max)) p.name];
  if (names.length <= 1) return names.join();
  return '${names.sublist(0, names.length - 1).join(', ')} e ${names.last}';
}
