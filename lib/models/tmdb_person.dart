class TmdbPerson {
  final int id;
  final String name;
  final String? profilePath;
  final String? character;
  final String? department;
  final String? biography;
  final String? birthday;
  final String? placeOfBirth;
  final int knownForCount;

  /// True when [character] is a crew role ("Regia"), not a part played.
  final bool crewRole;

  const TmdbPerson({
    required this.id,
    required this.name,
    this.profilePath,
    this.character,
    this.department,
    this.biography,
    this.birthday,
    this.placeOfBirth,
    this.knownForCount = 0,
    this.crewRole = false,
  });

  /// Same person shown with another role line (e.g. "Regia").
  TmdbPerson withRole(String role) => TmdbPerson(
    id: id,
    name: name,
    profilePath: profilePath,
    character: role,
    department: department,
    biography: biography,
    birthday: birthday,
    placeOfBirth: placeOfBirth,
    knownForCount: knownForCount,
    crewRole: true,
  );

  bool get isDirector => department == 'Directing';

  /// Main job in Italian, when TMDB states it.
  String? get roleLabel => switch (department) {
    'Acting' => 'Recitazione',
    'Directing' => 'Regia',
    'Writing' => 'Sceneggiatura',
    'Production' => 'Produzione',
    _ => null,
  };

  String get profileUrl =>
      profilePath == null ? '' : 'https://image.tmdb.org/t/p/w342$profilePath';

  static TmdbPerson? tryParse(Map<String, dynamic> json) {
    final id = json['id'];
    final name = (json['name'] ?? '').toString();
    if (id is! int || name.isEmpty) return null;
    return TmdbPerson(
      id: id,
      name: name,
      profilePath: json['profile_path'] as String?,
      character: (json['character'] ?? json['job'] ?? '').toString().isEmpty
          ? null
          : (json['character'] ?? json['job']).toString(),
      department: json['known_for_department'] as String?,
      biography: (json['biography'] ?? '').toString().isEmpty
          ? null
          : (json['biography']).toString(),
      birthday: json['birthday']?.toString(),
      placeOfBirth: json['place_of_birth']?.toString(),
      knownForCount: (json['known_for'] as List?)?.length ?? 0,
    );
  }
}

/// True when [query] names this person: every word of the query starts a
/// word of the name ("nolan", "chris nol"), accents and case ignored.
bool personNameMatches(String name, String query) {
  List<String> words(String s) =>
      _fold(s).split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toList();
  final wanted = words(query);
  if (wanted.isEmpty || wanted.join().length < 3) return false;
  final have = words(name);
  return wanted.every((w) => have.any((h) => h.startsWith(w)));
}

String _fold(String s) {
  const from = 'àáâãäåèéêëìíîïòóôõöùúûüñçýÿ';
  const to = 'aaaaaaeeeeiiiiooooouuuuncyy';
  final buffer = StringBuffer();
  for (final rune in s.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final i = from.indexOf(char);
    buffer.write(i < 0 ? char : to[i]);
  }
  return buffer.toString();
}
