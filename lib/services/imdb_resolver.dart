import 'foreground_http_client.dart';

import 'dart:convert';

import '../config/supabase_config.dart';

final _foregroundHttp = ForegroundHttpClient();

/// Resolves the IMDb id of a series (needed by IntroDB) from a TMDB id or
/// from the playlist title ("IT: Breaking Bad FHD S01E01" works too).
/// The TMDB lookup (external_ids / search/tv) runs on the app server so the
/// TMDB key never ships inside the app. Returns null on any failure.
class ImdbResolver {
  static final Map<String, String?> _cache = {};

  static Future<String?> getImdbId({
    int? tmdbId,
    String? title,
    bool isMovie = false,
  }) async {
    final kind = isMovie ? 'movie' : 'tv';
    final cacheKey = tmdbId != null
        ? '$kind:id:$tmdbId'
        : '$kind:t:${title ?? ''}';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];
    if (tmdbId == null && (title == null || title.trim().isEmpty)) return null;
    try {
      final uri = Uri.parse('${SupabaseConfig.apiBase}/imdb').replace(
        queryParameters: {
          'tmdb_id': ?tmdbId?.toString(),
          'title': ?title,
          'type': kind,
        },
      );
      final res = await _foregroundHttp
          .get(uri)
          .timeout(const Duration(seconds: 10));
      String? id;
      if (res.statusCode == 200) {
        final v = (jsonDecode(res.body) as Map)['imdb_id'];
        if (v is String && RegExp(r'^tt\d+$').hasMatch(v)) id = v;
      }
      // Cache only definitive answers: a timeout or server error must not
      // disable subtitles for the rest of the session.
      if (id != null || res.statusCode == 404) _cache[cacheKey] = id;
      return id;
    } catch (_) {
      return null;
    }
  }
}
