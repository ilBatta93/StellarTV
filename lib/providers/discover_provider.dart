import '../services/title_providers_service.dart';
import '../services/imdb_rating_service.dart';
import '../services/title_facet_index.dart';
import '../services/title_logo_cache.dart';
import '../services/segment_library.dart';
import '../services/platform_catalog_service.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/streaming_platform.dart';
import '../models/tmdb_item.dart';
import '../services/tmdb_service.dart';

class DiscoverProvider extends ChangeNotifier {
  final TmdbService tmdb;

  DiscoverProvider(this.tmdb) {
    // Platform badges must not depend on opening a filter: per-title
    // answers and the saved platform catalogs load right after start.
    TitleProvidersService.instance.attach(tmdb);
    unawaited(_openScores());
    SegmentLibrary.instance.load();
    PlatformCatalogService.instance.warmUpAll(tmdb);
  }

  bool _isLoading = false;
  String? _error;
  List<TmdbItem> _topMovies = [];
  List<TmdbItem> _topSeries = [];
  final Map<String, PlatformTops> _platformTops = {};
  List<TmdbItem> _forYou = [];
  String? _forYouSource;
  String _forYouSignature = '';
  List<TmdbItem> _forYouSeries = [];
  String? _forYouSeriesSource;
  String _forYouSeriesSignature = '';
  String _profileScope = '';

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<TmdbItem> get topMovies => _topMovies;
  List<TmdbItem> get topSeries => _topSeries;
  PlatformTops platformTop(StreamingPlatform p) =>
      _platformTops[p.name] ?? const PlatformTops();
  List<TmdbItem> get forYou => _forYou;
  String? get forYouSource => _forYouSource;
  List<TmdbItem> get forYouSeries => _forYouSeries;
  String? get forYouSeriesSource => _forYouSeriesSource;
  bool get hasData => _topMovies.isNotEmpty || _topSeries.isNotEmpty;

  Future<void> _openScores() async {
    await Future.wait([
      ImdbRatingService.instance.store.load(),
      TitleFacetIndex.instance.load(),
    ]);
    final index = TitleFacetIndex.instance;
    await index.mergeImdbStore(ImdbRatingService.instance.store.timedSnapshot);
    index.beginBulk();
    await TitleLogoCache.importResolved();
    index.endBulk();
    _primeVisible();
  }

  /// One shared-cache pass for the Top candidate lists, not one request per poster.
  /// The rows keep only titles present on the device, so the whole fetched
  /// page is primed, not merely the first ten names.
  void _primeVisible() {
    final items = <TmdbItem>[
      ..._topMovies,
      ..._topSeries,
      for (final tops in _platformTops.values) ...tops.movies,
      for (final tops in _platformTops.values) ...tops.series,
    ];
    if (items.isEmpty) return;
    ImdbRatingService.instance.prime(items);
  }

  TmdbItem? get featured {
    final pool = [
      ..._topMovies.take(3),
      ..._topSeries.take(2),
    ].where((e) => e.backdropPath != null).toList();
    return pool.isEmpty ? null : pool.first;
  }

  static const _cacheKey = 'discover_cache_v1';
  static const _cacheTtl = Duration(hours: 6);
  bool _cacheRead = false;
  Future<void>? _inFlight;
  DateTime? _freshAt;
  bool get _isFresh {
    final at = _freshAt;
    if (at == null) return false;
    final age = DateTime.now().difference(at);
    return !age.isNegative && age < _cacheTtl;
  }

  static List<Map<String, dynamic>> _enc(List<TmdbItem> l) =>
      l.map((e) => e.toJson()).toList();
  static List<TmdbItem> _dec(dynamic raw) => raw is List
      ? raw
            .whereType<Map>()
            .map((m) => TmdbItem.tryParse(m.cast<String, dynamic>()))
            .whereType<TmdbItem>()
            .toList()
      : <TmdbItem>[];

  /// Shows the last saved Top lists instantly (no network wait at startup),
  /// then refreshes them in background when older than [_cacheTtl].
  Future<bool> _readCache() async {
    if (_cacheRead) return _isFresh;
    _cacheRead = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return false;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _topMovies = _dec(m['movies']);
      _topSeries = _dec(m['series']);
      final plat = (m['platforms'] as Map?) ?? const {};
      for (final e in plat.entries) {
        final v = (e.value as Map?) ?? const {};
        _platformTops[e.key.toString()] = PlatformTops(
          movies: _dec(v['m']),
          series: _dec(v['s']),
        );
      }
      notifyListeners();
      _primeVisible();
      final at = DateTime.tryParse(m['at']?.toString() ?? '');
      // A platform added by an update (e.g. Disney+) has no saved Top yet:
      // refresh now instead of waiting for the cache to expire.
      final complete = StreamingPlatform.all.every(
        (p) => _platformTops.containsKey(p.name),
      );
      _freshAt = complete ? at : null;
      return _isFresh;
    } catch (_) {
      return false;
    }
  }

  Future<void> _writeCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode({
          'at': _freshAt?.toIso8601String(),
          'movies': _enc(_topMovies),
          'series': _enc(_topSeries),
          'platforms': {
            for (final e in _platformTops.entries)
              e.key: {'m': _enc(e.value.movies), 's': _enc(e.value.series)},
          },
        }),
      );
    } catch (_) {}
  }

  Future<void> load({bool force = false}) {
    return _inFlight ??= Future<void>.microtask(() async {
      try {
        await _refresh(force: force);
      } finally {
        _inFlight = null;
      }
    });
  }

  Future<void> _refresh({required bool force}) async {
    if (await _readCache() && !force) return;
    _isLoading = !hasData;
    _error = null;
    notifyListeners();
    try {
      final trending =
          Future.wait([tmdb.trending('movie'), tmdb.trending('tv')]).then((r) {
            _topMovies = r[0];
            _topSeries = r[1];
            _isLoading = false;
            notifyListeners();
          });
      var complete = true;
      final platforms = () async {
        final all = StreamingPlatform.all;
        for (var start = 0; start < all.length; start += 2) {
          await Future.wait(
            all.skip(start).take(2).map((p) async {
              try {
                _platformTops[p.name] = await tmdb.platformTop(p);
                notifyListeners();
              } catch (_) {
                complete = false;
                _platformTops.putIfAbsent(p.name, () => const PlatformTops());
              }
            }),
          );
        }
      }();
      await Future.wait([trending, platforms]);
      _freshAt = complete ? DateTime.now() : null;
      _primeVisible();
      await _writeCache();
    } catch (e) {
      if (!hasData) _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// "Consigliati per te": one row for films and one for series. Each uses
  /// the 3 most recent titles of its kind in the history (series episodes
  /// count once per series), asks TMDB for their recommendations (similar
  /// titles as fallback) and interleaves them, max 20, without the seeds.
  Future<void> loadForYou(
    List<Channel> history, {
    List<TmdbItem> liked = const [],
    Set<String> disliked = const {},
    String reactionSignature = '',
  }) async {
    final scope = reactionSignature.split(':').first;
    if (_profileScope != scope) {
      _profileScope = scope;
      _forYou = [];
      _forYouSeries = [];
      _forYouSource = null;
      _forYouSeriesSource = null;
      _forYouSignature = '';
      _forYouSeriesSignature = '';
      notifyListeners();
    }
    final movies = <Channel>[];
    final series = <Channel>[];
    final seenSeries = <String>{};
    for (final c in history) {
      if (c.type == ContentType.movie) {
        if (movies.length < 3) movies.add(c);
      } else if (c.type == ContentType.series || c.type == ContentType.anime) {
        final key = c.seriesKey ?? c.displaySeriesName.toLowerCase();
        if (series.length < 3 && seenSeries.add(key)) series.add(c);
      }
      if (movies.length >= 3 && series.length >= 3) break;
    }

    await Future.wait([
      _loadMovies(
        movies,
        liked.where((m) => m.isMovie).toList(),
        disliked,
        reactionSignature,
      ),
      _loadSeries(
        series,
        liked.where((m) => !m.isMovie).toList(),
        disliked,
        reactionSignature,
      ),
    ]);
  }

  Future<void> _loadMovies(
    List<Channel> seeds,
    List<TmdbItem> liked,
    Set<String> disliked,
    String reactions,
  ) async {
    final signature = '$reactions:${seeds.map((c) => c.id).join('|')}';
    if (signature == _forYouSignature) return;
    _forYouSignature = signature;
    final result = await _recommend(
      seeds,
      isMovie: true,
      liked: liked,
      disliked: disliked,
    );
    if (signature != _forYouSignature) return;
    if (result == null) {
      _forYouSignature = '';
      return;
    }
    _forYou = result.$1;
    _forYouSource = result.$2;
    notifyListeners();
  }

  Future<void> _loadSeries(
    List<Channel> seeds,
    List<TmdbItem> liked,
    Set<String> disliked,
    String reactions,
  ) async {
    final signature =
        '$reactions:${seeds.map((c) => c.seriesKey ?? c.displaySeriesName).join('|')}';
    if (signature == _forYouSeriesSignature) return;
    _forYouSeriesSignature = signature;
    final result = await _recommend(
      seeds,
      isMovie: false,
      liked: liked,
      disliked: disliked,
    );
    if (signature != _forYouSeriesSignature) return;
    if (result == null) {
      _forYouSeriesSignature = '';
      return;
    }
    _forYouSeries = result.$1;
    _forYouSeriesSource = result.$2;
    notifyListeners();
  }

  /// Null on a network failure (retried on the next Home build).
  Future<(List<TmdbItem>, String?)?> _recommend(
    List<Channel> seeds, {
    required bool isMovie,
    required List<TmdbItem> liked,
    required Set<String> disliked,
  }) async {
    if (seeds.isEmpty && liked.isEmpty) return (const <TmdbItem>[], null);
    try {
      final matches = await Future.wait(
        seeds.map(
          (c) => tmdb
              .findByTitle(
                isMovie ? c.name : c.displaySeriesName,
                isMovie: isMovie,
              )
              .catchError((_) => null),
        ),
      );
      final unique = <String, TmdbItem>{};
      for (final item in [
        ...liked.reversed,
        ...matches.whereType<TmdbItem>(),
      ]) {
        if (!disliked.contains(item.key)) {
          unique.putIfAbsent(item.key, () => item);
        }
      }
      final found = unique.values.take(5).toList();
      if (found.isEmpty) return (const <TmdbItem>[], null);
      final recs = await Future.wait(
        found.map(
          (m) => tmdb.recommendations(m).catchError((_) => <TmdbItem>[]),
        ),
      );
      final seen = {...disliked, ...found.map((e) => e.key)};
      final merged = <TmdbItem>[];
      for (var i = 0; i < 20; i++) {
        for (final list in recs) {
          if (i < list.length && seen.add(list[i].key)) merged.add(list[i]);
        }
      }
      return (merged.take(20).toList(), found.first.title);
    } catch (_) {
      return null;
    }
  }
}
