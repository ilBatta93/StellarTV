import 'dart:convert';

import 'title_logo_cache.dart';

import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';
import '../models/streaming_platform.dart';
import '../models/tmdb_item.dart';
import '../models/title_trailer.dart';
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

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String> params = const {},
  ]) async {
    final uri = Uri.parse(SupabaseConfig.tmdbProxyUrl)
        .replace(queryParameters: {'path': path, ...params});
    final http.Response res;
    try {
      res = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
              'apikey': SupabaseConfig.anonKey,
            },
          )
          .timeout(const Duration(seconds: 15));
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
      _get('trending/$mediaType/week', {
        'page': '2',
      }).catchError((_) => <String, dynamic>{}),
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
    StreamingPlatform platform,
    String region,
  ) async {
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
      return _dedupe([for (final p in pages) ..._parseResults(p, type: type)]);
    }

    final results = await Future.wait([fetch('movie'), fetch('tv')]);
    return PlatformTops(movies: results[0], series: results[1]);
  }

  /// Wider platform catalog used by the Film / Serie TV platform filter:
  /// up to [pages] TMDB pages of the platform's titles available in Italy,
  /// most popular first. Only TMDB is queried; the playlist never leaves the
  /// device (matching happens locally).
  Future<List<TmdbItem>> platformCatalog(
    StreamingPlatform platform, {
    required bool movies,
    int pages = 10,
  }) async {
    final type = movies ? 'movie' : 'tv';
    final out = <TmdbItem>[];
    // Sequential batches of 3 pages keep the TMDB request rate gentle.
    for (var start = 1; start <= pages; start += 3) {
      final batch = await Future.wait([
        for (var page = start; page < start + 3 && page <= pages; page++)
          _get('discover/$type', {
            'with_watch_providers': platform.providerIds,
            'watch_region': platform.region,
            'sort_by': 'popularity.desc',
            'page': '$page',
          }).catchError((_) => <String, dynamic>{}),
      ]);
      var empty = true;
      for (final body in batch) {
        final items = _parseResults(body, type: type);
        if (items.isNotEmpty) empty = false;
        out.addAll(items);
      }
      if (empty) break;
    }
    return _dedupe(out);
  }

  static List<TmdbItem> _dedupe(List<TmdbItem> items) {
    final seen = <String>{};
    return [
      for (final i in items)
        if (seen.add(i.key)) i,
    ];
  }

  final Map<String, Future<TmdbItem?>> _homeArtwork = {};
  Future<TmdbItem?> homeArtwork(String title, {required bool isMovie}) {
    final key = '${isMovie ? 'movie' : 'tv'}:$title';
    if (_homeArtwork.length >= 160 && !_homeArtwork.containsKey(key)) {
      _homeArtwork.remove(_homeArtwork.keys.first);
    }
    return _homeArtwork.putIfAbsent(
      key,
      () => findByTitle(title, isMovie: isMovie).catchError((_) => null),
    );
  }

  // Only focused banners request logos; share in-flight and cached results.
  final Map<String, Future<String?>> _titleLogos = {};
  Future<String?> titleLogo(TmdbItem item) {
    if (item.id <= 0) return Future<String?>.value(null);
    if (_titleLogos.length >= 160 && !_titleLogos.containsKey(item.key)) {
      _titleLogos.remove(_titleLogos.keys.first);
    }
    return _titleLogos.putIfAbsent(item.key, () async {
      try {
        final cached = await TitleLogoCache.read(item.key);
        if (cached != null) return cached.url;
        final shared = await sharedLogo(item);
        if (shared != null) {
          await TitleLogoCache.write(item.key, shared.url);
          return shared.url;
        }
        final body = await _get('${item.mediaType}/${item.id}/images', {
          // Only Italian or English logos: TMDB also returns untagged
          // images that can carry text in any other language.
          'include_image_language': 'it,en',
        });
        final url = selectTitleLogo(body);
        await TitleLogoCache.write(item.key, url);
        return url;
      } catch (_) {
        _titleLogos.remove(item.key);
        return null; // Retry on the next presentation after a transient failure.
      }
    });
  }

  /// Shared cloud cache of public TMDB paths, common to every installation.
  /// Returns null when unavailable so the direct TMDB lookup still runs.
  /// Only TMDB title/id are sent: provider names, URLs or covers never leave
  /// the device.
  Future<TitleLogoEntry?> sharedLogo(TmdbItem item) async {
    try {
      final res = await http
          .post(
            Uri.parse('${SupabaseConfig.apiBase}/artwork'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'items': [
                {
                  'title': item.title,
                  'type': item.mediaType,
                  'tmdb_id': item.id,
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      return parseSharedLogo(jsonDecode(res.body));
    } catch (_) {
      return null;
    }
  }

  static TitleLogoEntry? parseSharedLogo(Object? body) {
    if (body is! Map || body['results'] is! List) return null;
    final list = body['results'] as List;
    if (list.isEmpty || list.first is! Map) return null;
    final row = list.first as Map;
    if (row['tmdb_id'] is! int) return null;
    final path = row['logo_path'];
    if (path == null) return const TitleLogoEntry(null);
    if (path is! String ||
        !RegExp(r'^/[a-zA-Z0-9_.-]+\.(png|jpg|webp)$').hasMatch(path)) {
      return null;
    }
    return TitleLogoEntry('https://image.tmdb.org/t/p/w500$path');
  }

  static String? selectTitleLogo(Map<String, dynamic> body) {
    final raw = body['logos'];
    if (raw is! List) return null;
    final logos = raw
        .whereType<Map<String, dynamic>>()
        .where(
          (e) =>
              e['file_path'] is String &&
              (e['file_path'] as String).startsWith('/') &&
              RegExp(r'^/[a-zA-Z0-9_.-]+\.(png|jpg|webp)$')
                  .hasMatch(e['file_path'] as String),
        )
        .toList();
    // Strictly Italian or English: untagged (null) and other languages are
    // discarded, because untagged logos can show text in any language.
    int priority(Object? language) => language == 'it'
        ? 0
        : language == 'en'
        ? 1
        : 2;
    logos.sort((a, b) {
      final language = priority(a['iso_639_1'])
          .compareTo(priority(b['iso_639_1']));
      if (language != 0) return language;
      return ((b['vote_average'] as num?) ?? 0).compareTo(
        (a['vote_average'] as num?) ?? 0,
      );
    });
    final preferred = logos.where((e) => priority(e['iso_639_1']) < 2);
    if (preferred.isEmpty) return null;
    return 'https://image.tmdb.org/t/p/w500${preferred.first['file_path']}';
  }

  final Map<String, Future<TitleTrailer?>> _trailers = {};
  Future<TitleTrailer?> trailer(TmdbItem item) {
    if (item.id <= 0) return Future.value(null);
    if (_trailers.length >= 160 && !_trailers.containsKey(item.key)) {
      _trailers.remove(_trailers.keys.first);
    }
    return _trailers.putIfAbsent(item.key, () async {
      try {
        final italian = TitleTrailer.select(
          await _get('${item.mediaType}/${item.id}/videos', {
            'language': 'it-IT',
          }),
          'it',
        );
        if (italian != null) return italian;
        return TitleTrailer.select(
          await _get('${item.mediaType}/${item.id}/videos', {
            'language': 'en-US',
          }),
          'en',
        );
      } catch (_) {
        _trailers.remove(item.key);
        return null;
      }
    });
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

  Future<TmdbPerson?> personDetails(
    int personId, {
    String language = 'it-IT',
  }) async {
    try {
      final body = await _get('person/$personId', {'language': language});
      return TmdbPerson.tryParse(body);
    } catch (_) {
      return null;
    }
  }

  Future<List<TmdbItem>> personCredits(
    int personId, {
    String language = 'it-IT',
  }) async {
    final body = await _get('person/$personId/combined_credits', {
      'language': language,
    });
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

  Future<TmdbItem?> findByTitle(
    String rawTitle, {
    required bool isMovie,
  }) async {
    final cleaned = cleanTitle(rawTitle);
    if (cleaned.isEmpty) return null;
    final body = await _get(isMovie ? 'search/movie' : 'search/tv', {
      'query': cleaned,
    });
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
      RegExp(
        r'\b(4K|UHD|FHD|HD|SD|HEVC|H265|MULTI|SUB ITA|ITA|ENG)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    t = t.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ');
    t = t.replaceAll(RegExp(r'[_.|]'), ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
