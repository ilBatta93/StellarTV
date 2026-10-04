import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/supabase_config.dart';
import '../models/streaming_platform.dart';
import '../models/tmdb_item.dart';
import '../models/tmdb_person.dart';

class TmdbException implements Exception {
  final String message;
  TmdbException(this.message);
  @override
  String toString() => message;
}

class PlatformTops {
  final List<TmdbItem> movies;
  final List<TmdbItem> series;
  const PlatformTops({this.movies = const [], this.series = const []});
  bool get isEmpty => movies.isEmpty && series.isEmpty;
}

class TmdbService {
  static const _fallbackRegion = 'US';

  Future<Map<String, dynamic>> _get(String path,
      [Map<String, String> params = const {}]) async {
    final uri = Uri.parse(SupabaseConfig.tmdbProxyUrl)
        .replace(queryParameters: {'path': path, ...params});
    final http.Response res;
    try {
      res = await http.get(uri, headers: {
        'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
        'apikey': SupabaseConfig.anonKey,
      }).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw TmdbException('Connessione non disponibile');
    }
    if (res.statusCode == 503) {
      throw TmdbException('Il catalogo TMDB non è ancora configurato');
    }
    if (res.statusCode != 200) {
      throw TmdbException('Impossibile caricare il catalogo');
    }
    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) {
      throw TmdbException('Risposta non valida');
    }
    return body;
  }

  List<TmdbItem> _parseResults(Map<String, dynamic> body, {String? type}) {
    final results = body['results'];
    if (results is! List) return [];
    return results
        .whereType<Map<String, dynamic>>()
        .map((e) => TmdbItem.tryParse(e, fallbackType: type))
        .whereType<TmdbItem>()
        .toList();
  }

  /// Trending titles (two pages): the Home keeps only those that are in the
  /// playlist, so it fetches more than ten candidates.
  Future<List<TmdbItem>> trending(String mediaType) async {
    final pages = await Future.wait([
      _get('trending/$mediaType/week', {'page': '1'}),
      _get('trending/$mediaType/week', {'page': '2'})
          .catchError((_) => <String, dynamic>{}),
    ]);
    return _dedupe([
      for (final p in pages) ..._parseResults(p, type: mediaType),
    ]);
  }

  /// Most popular films and series of a streaming platform, kept separate.
  Future<PlatformTops> platformTop(StreamingPlatform platform) async {
    var tops = await _platformTopForRegion(platform, platform.region);
    if (tops.isEmpty && platform.region != _fallbackRegion) {
      tops = await _platformTopForRegion(platform, _fallbackRegion);
    }
    return tops;
  }

  Future<PlatformTops> _platformTopForRegion(
      StreamingPlatform platform, String region) async {
    Future<List<TmdbItem>> fetch(String type) async {
      final pages = await Future.wait([
        for (final page in ['1', '2'])
          _get('discover/$type', {
            'with_watch_providers': platform.providerIds,
            'watch_region': region,
            'sort_by': 'popularity.desc',
            'page': page,
          }).catchError((_) => <String, dynamic>{}),
      ]);
      return _dedupe([
        for (final p in pages) ..._parseResults(p, type: type),
      ]);
    }

    final results = await Future.wait([fetch('movie'), fetch('tv')]);
    return PlatformTops(movies: results[0], series: results[1]);
  }

  static List<TmdbItem> _dedupe(List<TmdbItem> items) {
    final seen = <String>{};
    return [for (final i in items) if (seen.add(i.key)) i];
  }

  Future<List<TmdbItem>> recommendations(TmdbItem item) async {
    final body = await _get('${item.mediaType}/${item.id}/recommendations');
    final items = _parseResults(body, type: item.mediaType);
    if (items.isNotEmpty) return items;
    final similar = await _get('${item.mediaType}/${item.id}/similar');
    return _parseResults(similar, type: item.mediaType);
  }

  Future<List<TmdbItem>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final body = await _get('search/multi', {'query': query.trim()});
    return _parseResults(body);
  }

  Future<List<TmdbPerson>> cast(TmdbItem item) async {
    try {
      final body = await _get('${item.mediaType}/${item.id}/credits');
      final cast = body['cast'];
      if (cast is! List) return [];
      return cast
          .whereType<Map<String, dynamic>>()
          .map(TmdbPerson.tryParse)
          .whereType<TmdbPerson>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<TmdbPerson?> personDetails(int personId,
      {String language = 'it-IT'}) async {
    try {
      final body = await _get('person/$personId', {'language': language});
      return TmdbPerson.tryParse(body);
    } catch (_) {
      return null;
    }
  }

  Future<List<TmdbItem>> personCredits(int personId,
      {String language = 'it-IT'}) async {
    final body =
        await _get('person/$personId/combined_credits', {'language': language});
    final cast = body['cast'];
    if (cast is! List) return [];
    final seen = <String>{};
    final items = <TmdbItem>[];
    for (final raw in cast) {
      if (raw is! Map<String, dynamic>) continue;
      final item = TmdbItem.tryParse(raw);
      if (item != null && seen.add(item.key)) items.add(item);
    }
    items.sort((a, b) => b.popularity.compareTo(a.popularity));
    return items;
  }

  Future<List<TmdbPerson>> searchPeople(String query) async {
    if (query.trim().isEmpty) return [];
    final body = await _get('search/person', {'query': query.trim()});
    final results = body['results'];
    if (results is! List) return [];
    return results
        .whereType<Map<String, dynamic>>()
        .map(TmdbPerson.tryParse)
        .whereType<TmdbPerson>()
        .toList();
  }

  Future<TmdbItem?> findByTitle(String rawTitle, {required bool isMovie}) async {
    final cleaned = cleanTitle(rawTitle);
    if (cleaned.isEmpty) return null;
    final body =
        await _get(isMovie ? 'search/movie' : 'search/tv', {'query': cleaned});
    final items = _parseResults(body, type: isMovie ? 'movie' : 'tv');
    if (items.isEmpty) return null;
    // Prefer an exact title match (and the playlist year when present).
    String norm(String v) =>
        v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9à-ÿ]+'), ' ').trim();
    final target = norm(cleaned);
    final year = RegExp(r'\b(19|20)\d{2}\b').firstMatch(rawTitle)?.group(0);
    final exact = items.where((e) => norm(e.title) == target).toList();
    if (year != null) {
      for (final e in exact) {
        if (e.year == year) return e;
      }
    }
    return exact.isNotEmpty ? exact.first : items.first;
  }

  static String cleanTitle(String raw) {
    var t = raw;
    t = t.replaceAll(RegExp(r'^\s*[A-Z]{2,3}\s*[:|\-]\s*'), '');
    t = t.replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)'), ' ');
    t = t.replaceAll(
        RegExp(r'\b(4K|UHD|FHD|HD|SD|HEVC|H265|MULTI|SUB ITA|ITA|ENG)\b',
            caseSensitive: false),
        ' ');
    t = t.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ');
    t = t.replaceAll(RegExp(r'[_.|]'), ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
