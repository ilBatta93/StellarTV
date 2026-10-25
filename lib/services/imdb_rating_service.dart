import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/tmdb_item.dart';
import 'foreground_http_client.dart';
import 'playback_work_policy.dart';
import 'title_facet_index.dart';
import 'title_metadata_store.dart';

/// Official IMDb ratings, saved on the device (30 days) and requested in
/// small batches only for titles actually shown. Null rating = unknown on
/// IMDb, so the UI waits until that lookup completes before using TMDB.
///
/// The open title and its visible episodes go first. Catalog scrolling only
/// reads the shared cache and never waits in front of a title page.
class ImdbRatingService {
  ImdbRatingService._();
  static final instance = ImdbRatingService._();

  final store = TitleMetadataStore<double>(
    fileName: 'stellartv_imdb_ratings_v1.json',
    encode: (v) => v,
    decode: (raw) => raw is num ? raw.toDouble() : null,
  );
  final _http = ForegroundHttpClient();
  final List<String> _titlePriority = [];
  final List<String> _episodePriority = [];
  final Set<String> _queued = {};
  final Set<String> _settled = {};
  final Set<String> _asked = {};
  final Set<String> _inflight = {};
  // Keys only looked up in the shared cloud cache (posters and sorting):
  // never trigger an external IMDb request, except one attempt for a
  // poster actually on screen when the shared cache has no vote.
  final Set<String> _cacheQueued = {};
  final Set<String> _cacheAsked = {};
  final Set<String> _reveal = {};
  Timer? _timer;
  bool _running = false;

  static String keyOf(TmdbItem item) =>
      '${item.isMovie ? 'movie' : 'tv'}:${item.id}';

  static String episodeKey(int id, int season, int episode) =>
      'tv:$id:$season:$episode';

  /// Stored value, or 0 once a lookup confirmed IMDb has none. No request.
  double? peek(TmdbItem item) => _value(keyOf(item));

  Map<String, double> exportScores() => store.snapshot();

  double? _value(String key) {
    final v = store.valueOf(key);
    return v ?? (_settled.contains(key) ? 0 : null);
  }

  /// The title currently on screen. Jumps ahead of episode and catalog work.
  void prioritizeTitle(String key) {
    if (!_enqueue(_titlePriority, key)) return;
    _episodePriority.remove(key);
    _kick(const Duration(milliseconds: 40));
  }

  /// Episodes of the open season, behind the series or film rating.
  void prioritizeEpisodes(Iterable<String> keys) {
    var added = false;
    for (final key in keys) {
      if (_titlePriority.contains(key)) continue;
      added = _enqueue(_episodePriority, key) || added;
    }
    if (added) _kick(const Duration(milliseconds: 40));
  }

  bool _enqueue(List<String> lane, String key) {
    if (TitleMetadataStore.disabled || store.isFresh(key)) return false;
    if (_settled.contains(key) ||
        _inflight.contains(key) ||
        lane.contains(key)) {
      return false;
    }
    _queued.remove(key);
    _cacheQueued.remove(key);
    lane.add(key);
    _asked.add(key);
    return true;
  }

  double? episodeRating(
    int id,
    int season,
    int episode, {
    bool request = true,
    bool priority = false,
  }) {
    final key = episodeKey(id, season, episode);
    if (request) {
      if (priority) {
        prioritizeEpisodes([key]);
      } else {
        _requestKey(key);
      }
    }
    return _value(key);
  }

  void _requestKey(String key) {
    if (!TitleMetadataStore.disabled &&
        !store.isFresh(key) &&
        !_titlePriority.contains(key) &&
        !_episodePriority.contains(key) &&
        !_inflight.contains(key) &&
        _asked.add(key)) {
      _queued.add(key);
      _kick(const Duration(milliseconds: 400));
    }
  }

  /// Poster on screen. Shared cache first; one full lookup if that cache
  /// has no vote, so the badge can leave the pending state.
  void reveal(TmdbItem item) {
    if (TitleMetadataStore.disabled) return;
    final key = keyOf(item);
    if (store.valueOf(key) != null ||
        _settled.contains(key) ||
        _inflight.contains(key) ||
        _queued.contains(key) ||
        _titlePriority.contains(key)) {
      return;
    }
    if (!_cacheAsked.contains(key) || _cacheQueued.contains(key)) {
      _reveal.add(key);
      prime([item]);
      return;
    }
    _promoteReveal(key);
    if (_queued.isNotEmpty) _kick(const Duration(milliseconds: 400));
  }

  bool _promoteReveal(String key) {
    if (!_reveal.remove(key)) return false;
    if (store.valueOf(key) != null ||
        _settled.contains(key) ||
        _inflight.contains(key) ||
        _queued.contains(key) ||
        _titlePriority.contains(key) ||
        _episodePriority.contains(key)) {
      return false;
    }
    if (!_asked.add(key)) return false;
    _queued.add(key);
    return true;
  }

  /// Fills the device cache from the shared cache only (no external call).
  void prime(Iterable<TmdbItem> items) {
    if (TitleMetadataStore.disabled) return;
    for (final item in items) {
      final key = keyOf(item);
      if (store.isFresh(key) ||
          TitleFacetIndex.instance.imdbFresh(key) ||
          _titlePriority.contains(key) ||
          _settled.contains(key)) {
        continue;
      }
      if (_cacheAsked.add(key)) _cacheQueued.add(key);
    }
    if (_cacheQueued.isNotEmpty) _kick(const Duration(milliseconds: 400));
  }

  /// IMDb rating, 0 when IMDb has none, null while unknown.
  /// [priority] is the open title: it is served before catalog lookups.
  double? ratingOf(TmdbItem item, {bool request = true, bool priority = false}) {
    final key = keyOf(item);
    if (request) {
      if (priority) {
        prioritizeTitle(key);
      } else {
        _requestKey(key);
      }
    }
    return _value(key);
  }

  void _kick(Duration delay) {
    if (_running) return;
    _timer ??= Timer(delay, _flush);
  }

  bool get _hasWork =>
      _titlePriority.isNotEmpty ||
      _episodePriority.isNotEmpty ||
      _queued.isNotEmpty ||
      _cacheQueued.isNotEmpty;

  List<String> _take(List<String> lane, int count) {
    if (count <= 0 || lane.isEmpty) return const [];
    final n = count < lane.length ? count : lane.length;
    final batch = lane.sublist(0, n);
    lane.removeRange(0, n);
    return batch;
  }

  Future<void> _flush() async {
    _timer = null;
    if (_running) return;
    _running = true;
    try {
      await store.load();
      while (_hasWork) {
        if (PlaybackWorkPolicy.instance.blocksGuide) {
          _timer = Timer(const Duration(seconds: 30), _flush);
          return;
        }
        final priority = [
          ..._take(_titlePriority, 40),
          ..._take(_episodePriority, 40),
        ];
        final List<String> batch;
        final bool cacheOnly;
        if (priority.isNotEmpty) {
          batch = priority.take(40).toList();
          if (priority.length > 40) {
            _episodePriority.insertAll(0, priority.skip(40));
          }
          cacheOnly = false;
        } else if (_queued.isNotEmpty) {
          batch = _queued.take(40).toList();
          _queued.removeAll(batch);
          cacheOnly = false;
        } else {
          batch = _cacheQueued.take(40).toList();
          _cacheQueued.removeAll(batch);
          cacheOnly = true;
        }
        batch.removeWhere(store.isFresh);
        if (batch.isEmpty) continue;
        _inflight.addAll(batch);
        final promote = <String>[];
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
          if (res.statusCode != 200) {
            throw const FormatException('IMDb unavailable');
          }
          final body = jsonDecode(res.body);
          final stored = <String>{};
          for (final r
              in (body is Map ? body['results'] as List? : null) ?? const []) {
            if (r is! Map || r['known'] != true) continue;
            final rating = r['rating'];
            final key = r['season'] is num && r['episode'] is num
                ? episodeKey(
                    (r['id'] as num).toInt(),
                    (r['season'] as num).toInt(),
                    (r['episode'] as num).toInt(),
                  )
                : '${r['type']}:${r['id']}';
            stored.add(key);
            final score = rating is num ? rating.toDouble() : 0.0;
            store.put(key, score);
            TitleFacetIndex.instance.putImdb(
              mediaKey: key,
              rating: score,
              imdbId: r['imdb_id'] is String ? r['imdb_id'] as String : null,
            );
          }
          if (cacheOnly) {
            for (final key in batch) {
              if (stored.contains(key)) {
                _reveal.remove(key);
              } else if (_reveal.contains(key)) {
                promote.add(key);
              }
            }
          }
        } catch (_) {
          // Do not persist transport failures as confirmed IMDb absence.
          if (cacheOnly) {
            for (final key in batch) {
              if (_reveal.contains(key)) _cacheAsked.remove(key);
            }
          }
        } finally {
          _inflight.removeAll(batch);
          for (final key in promote) {
            _promoteReveal(key);
          }
          if (!cacheOnly) {
            _settled.addAll(batch);
            store.notifyAvailabilityChanged();
          }
        }
      }
    } finally {
      _running = false;
      if (_hasWork && _timer == null) _kick(const Duration(milliseconds: 40));
    }
  }
}
