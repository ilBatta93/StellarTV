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
  });

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
