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

  DiscoverProvider(this.tmdb);

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
    if (_cacheRead) return false;
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
      final at = DateTime.tryParse(m['at']?.toString() ?? '');
      return at != null && DateTime.now().difference(at) < _cacheTtl;
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
          'at': DateTime.now().toIso8601String(),
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

  Future<void> load({bool force = false}) async {
    if (_isLoading) return;
    final fresh = await _readCache();
    if (fresh && !force) return;
    _isLoading = !hasData;
    _error = null;
    notifyListeners();
    try {
      // Everything in parallel: trending and every platform at once.
      final trending =
          Future.wait([tmdb.trending('movie'), tmdb.trending('tv')]).then((r) {
            _topMovies = r[0];
            _topSeries = r[1];
            _isLoading = false;
            notifyListeners();
          });
      final platforms = Future.wait(
        StreamingPlatform.all.map((p) async {
          try {
            final tops = await tmdb.platformTop(p);
            _platformTops[p.name] = tops;
            notifyListeners();
          } catch (_) {
            _platformTops.putIfAbsent(p.name, () => const PlatformTops());
          }
        }),
      );
      await Future.wait([trending, platforms]);
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
  Future<void> loadForYou(List<Channel> history) async {
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
    await Future.wait([_loadMovies(movies), _loadSeries(series)]);
  }

  Future<void> _loadMovies(List<Channel> seeds) async {
    final signature = seeds.map((c) => c.id).join('|');
    if (signature == _forYouSignature) return;
    _forYouSignature = signature;
    final result = await _recommend(seeds, isMovie: true);
    if (result == null) {
      _forYouSignature = '';
      return;
    }
    _forYou = result.$1;
    _forYouSource = result.$2;
    notifyListeners();
  }

  Future<void> _loadSeries(List<Channel> seeds) async {
    final signature = seeds
        .map((c) => c.seriesKey ?? c.displaySeriesName)
        .join('|');
    if (signature == _forYouSeriesSignature) return;
    _forYouSeriesSignature = signature;
    final result = await _recommend(seeds, isMovie: false);
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
  }) async {
    if (seeds.isEmpty) return (const <TmdbItem>[], null);
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
      final found = matches.whereType<TmdbItem>().toList();
      if (found.isEmpty) return (const <TmdbItem>[], null);
      final recs = await Future.wait(
        found.map(
          (m) => tmdb.recommendations(m).catchError((_) => <TmdbItem>[]),
        ),
      );
      final seen = found.map((e) => e.key).toSet();
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
