import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';

/// Resolves the IMDb id of a series (needed by IntroDB) from a TMDB id or
/// from the playlist title ("IT: Breaking Bad FHD S01E01" works too).
/// The TMDB lookup (external_ids / search/tv) runs on the app server so the
/// TMDB key never ships inside the app. Returns null on any failure.
class ImdbResolver {
  static final Map<String, String?> _cache = {};

  static Future<String?> getImdbId({int? tmdbId, String? title}) async {
    final cacheKey = tmdbId != null ? 'id:$tmdbId' : 't:${title ?? ''}';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];
    if (tmdbId == null && (title == null || title.trim().isEmpty)) return null;
    try {
      final uri = Uri.parse('${SupabaseConfig.apiBase}/imdb').replace(
        queryParameters: {
          if (tmdbId != null) 'tmdb_id': '$tmdbId',
          if (title != null) 'title': title,
        },
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      String? id;
      if (res.statusCode == 200) {
        final v = (jsonDecode(res.body) as Map)['imdb_id'];
        if (v is String && RegExp(r'^tt\d+$').hasMatch(v)) id = v;
      }
      _cache[cacheKey] = id;
      return id;
    } catch (_) {
      return null;
    }
  }
}
