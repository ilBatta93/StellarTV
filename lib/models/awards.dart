/// Oscar and Emmy nominees for the Home awards row, as served by the site's
/// `/api/public/awards` (twin: `src/lib/awards.ts`). Nominee lists arrive
/// winner first.
class AwardCategory {
  const AwardCategory({
    required this.id,
    required this.award,
    required this.label,
  });

  final String id;

  /// `oscar` or `emmy`.
  final String award;
  final String label;

  /// "Oscar · Miglior film".
  String get fullLabel => '${award == 'emmy' ? 'Emmy' : 'Oscar'} · $label';
}

class AwardNominee {
  const AwardNominee({
    required this.id,
    required this.movie,
    required this.title,
    required this.winner,
  });

  /// TMDB id; [movie] tells the type (a TV film can be a limited series).
  final int id;
  final bool movie;
  final String title;
  final bool winner;
}

class AwardsCatalog {
  const AwardsCatalog({required this.categories, required this.years});

  final List<AwardCategory> categories;

  /// Ceremony year -> category id -> nominees, winner first.
  final Map<int, Map<String, List<AwardNominee>>> years;

  static const empty = AwardsCatalog(categories: [], years: {});

  bool get isEmpty => years.isEmpty;

  /// Ceremony years, newest first.
  List<int> get yearsDesc => years.keys.toList()..sort((a, b) => b - a);

  /// Categories with nominees in [year], in the site's order.
  List<AwardCategory> categoriesIn(int year) => [
    for (final c in categories)
      if (years[year]?[c.id]?.isNotEmpty ?? false) c,
  ];

  List<AwardNominee> nominees(int year, String category) =>
      years[year]?[category] ?? const [];

  /// Unknown or malformed parts are skipped, never thrown.
  static AwardsCatalog fromJson(Object? json) {
    if (json is! Map) return empty;
    final categories = <AwardCategory>[
      for (final c in json['categories'] is List ? json['categories'] : [])
        if (c is Map && c['id'] is String && c['label'] is String)
          AwardCategory(
            id: c['id'],
            award: c['award'] == 'emmy' ? 'emmy' : 'oscar',
            label: c['label'],
          ),
    ];
    final years = <int, Map<String, List<AwardNominee>>>{};
    final rawYears = json['years'];
    if (rawYears is Map) {
      for (final MapEntry(:key, :value) in rawYears.entries) {
        final year = int.tryParse('$key');
        if (year == null || value is! Map) continue;
        final byCategory = <String, List<AwardNominee>>{};
        for (final MapEntry(key: category, value: list) in value.entries) {
          if (list is! List) continue;
          final nominees = [
            for (final n in list)
              if (n is Map && n['id'] is int && (n['id'] as int) > 0)
                AwardNominee(
                  id: n['id'],
                  movie: n['media'] != 'tv',
                  title: n['title'] is String ? n['title'] : '',
                  winner: n['winner'] == true,
                ),
          ];
          if (nominees.isNotEmpty) byCategory['$category'] = nominees;
        }
        if (byCategory.isNotEmpty) years[year] = byCategory;
      }
    }
    return AwardsCatalog(categories: categories, years: years);
  }
}
