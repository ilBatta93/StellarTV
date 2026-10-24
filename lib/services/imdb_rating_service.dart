import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/tmdb_item.dart';
import 'foreground_http_client.dart';
import 'playback_work_policy.dart';
import 'title_metadata_store.dart';

/// Official IMDb ratings, saved on the device (30 days) and requested in
/// small batches only for titles actually shown. Null rating = unknown on
/// IMDb, so the UI keeps the TMDB vote.
class ImdbRatingService {
  ImdbRatingService._();
  static final instance = ImdbRatingService._();

  final store = TitleMetadataStore<double>(
    fileName: 'stellartv_imdb_ratings_v1.json',
    encode: (v) => v,
    decode: (raw) => raw is num ? raw.toDouble() : null,
  );
  final _http = ForegroundHttpClient();
  final Set<String> _queued = {};
  final Set<String> _asked = {};
  // Keys only looked up in the shared cloud cache (sorting): never trigger
  // an external IMDb request, so a 10k title sort costs zero OMDb calls.
  final Set<String> _cacheQueued = {};
  final Set<String> _cacheAsked = {};
  Timer? _timer;
  bool _running = false;

  static String keyOf(TmdbItem item) =>
      '${item.isMovie ? 'movie' : 'tv'}:${item.id}';

  static String episodeKey(int id, int season, int episode) =>
      'tv:$id:$season:$episode';
  double? episodeRating(
    int id,
    int season,
    int episode, {
    bool request = true,
  }) {
    final key = episodeKey(id, season, episode);
    if (request) _requestKey(key);
    return store.valueOf(key);
  }

  void _requestKey(String key) {
    if (!TitleMetadataStore.disabled &&
        !store.isFresh(key) &&
        _asked.add(key)) {
      _queued.add(key);
      _timer ??= Timer(const Duration(milliseconds: 400), _flush);
    }
  }

  /// Fills the device cache from the shared cache only (no external call).
  void prime(Iterable<TmdbItem> items) {
    if (TitleMetadataStore.disabled) return;
    for (final item in items) {
      final key = keyOf(item);
      if (store.valueOf(key) == null && _cacheAsked.add(key)) {
        _cacheQueued.add(key);
      }
    }
    if (_cacheQueued.isNotEmpty) {
      _timer ??= Timer(const Duration(milliseconds: 400), _flush);
    }
  }

  /// IMDb rating, 0 when IMDb has none, null while unknown.
  double? ratingOf(TmdbItem item) {
    final key = keyOf(item);
    final v = store.valueOf(key);
    _requestKey(key);
    return v;
  }

  Future<void> _flush() async {
    _timer = null;
    if (_running) return;
    _running = true;
    try {
      await store.load();
      while (_queued.isNotEmpty || _cacheQueued.isNotEmpty) {
        if (PlaybackWorkPolicy.instance.blocksGuide) {
          _timer = Timer(const Duration(seconds: 30), _flush);
          return;
        }
        final cacheOnly = _queued.isEmpty;
        final source = cacheOnly ? _cacheQueued : _queued;
        final batch = source.take(40).toList();
        source.removeAll(batch);
        String bearer = SupabaseConfig.anonKey;
        try {
          bearer =
              Supabase.instance.client.auth.currentSession?.accessToken ??
              bearer;
        } catch (_) {}
        try {
          final res = await _http
              .post(
                Uri.parse('${SupabaseConfig.apiBase}/imdb-ratings'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $bearer',
                },
                body: jsonEncode({
                  if (cacheOnly) 'cacheOnly': true,
                  'items': [
                    for (final k in batch)
                      {
                        'type': k.split(':').first,
                        'id': int.parse(k.split(':')[1]),
                        if (k.split(':').length == 4) ...{
                          'season': int.parse(k.split(':')[2]),
                          'episode': int.parse(k.split(':')[3]),
                        },
                      },
                  ],
                }),
              )
              .timeout(const Duration(seconds: 25));
          if (res.statusCode != 200) continue;
          final body = jsonDecode(res.body);
          for (final r
              in (body is Map ? body['results'] as List? : null) ?? const []) {
            if (r is! Map || r['known'] != true) continue;
            final rating = r['rating'];
            store.put(
              r['season'] is num && r['episode'] is num
                  ? episodeKey(
                      (r['id'] as num).toInt(),
                      (r['season'] as num).toInt(),
                      (r['episode'] as num).toInt(),
                    )
                  : '${r['type']}:${r['id']}',
              rating is num ? rating.toDouble() : 0,
            );
          }
        } catch (_) {
          // Offline: TMDB vote stays visible; retried at the next start.
        }
      }
    } finally {
      _running = false;
    }
  }
}
