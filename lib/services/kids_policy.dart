/// Strict, pure profile policy shared by every catalog surface.
class KidsPolicy {
  static const blockedGenres = {
    27,
    53,
    80,
    28,
    10759,
    10749,
    10764,
    10763,
    18,
    10752,
    10768,
  };
  static const allowedGenres = {16, 10762, 10751};
  static final allowedCategory = RegExp(
    r'\b(animation|animated|animazione|cartoon|cartoons|cartoni(?:\s+animati)?|kids?|children|bambini|bimbi|family|famiglia)\b',
    caseSensitive: false,
  );
  static final primaryCategory = RegExp(
    r'\b(animation|animated|animazione|cartoon|cartoons|cartoni(?:\s+animati)?|kids?|children|bambini|bimbi)\b',
    caseSensitive: false,
  );
  static final blockedCategory = RegExp(
    r'\b(horror|thriller|crime|criminale|action|azione|romance|romantico|romantici|reality|news|notizie|drama|drammatico|drammatici|war|guerra|adulti|adult|xxx)\b',
    caseSensitive: false,
  );
  static const certifications = {
    'US': {'G', 'PG', 'TV-Y', 'TV-Y7', 'TV-Y7-FV', 'TV-G', 'TV-PG'},
    'IT': {'T', '0+', '6+'},
    'GB': {'U', 'PG'},
    'DE': {'0', '6'},
    'FR': {'U', 'TP'},
  };

  static bool allows({
    required String category,
    List<int> genres = const [],
    String certification = '',
  }) {
    if (blockedCategory.hasMatch(category) ||
        genres.any(blockedGenres.contains)) {
      return false;
    }
    final categoryAllowed = allowedCategory.hasMatch(category);
    // Generic IPTV categories need confirmed Animation/Kids, not just Family.
    if (!categoryAllowed && !genres.any((g) => g == 16 || g == 10762)) {
      return false;
    }
    final parts = certification.trim().toUpperCase().split(':');
    final cert = parts.last;
    if (!{'', 'UNKNOWN', 'UNRATED', 'NR', 'N/A'}.contains(cert)) {
      final country = parts.length > 1 ? parts.first : 'US';
      return certifications[country]?.contains(cert) ?? false;
    }
    return primaryCategory.hasMatch(category) ||
        (genres.isNotEmpty && (genres.first == 16 || genres.first == 10762));
  }
}
