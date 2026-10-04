import 'package:flutter/foundation.dart';
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

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<TmdbItem> get topMovies => _topMovies;
  List<TmdbItem> get topSeries => _topSeries;
  PlatformTops platformTop(StreamingPlatform p) =>
      _platformTops[p.name] ?? const PlatformTops();
  List<TmdbItem> get forYou => _forYou;
  String? get forYouSource => _forYouSource;
  bool get hasData => _topMovies.isNotEmpty || _topSeries.isNotEmpty;

  TmdbItem? get featured {
    final pool = [..._topMovies.take(3), ..._topSeries.take(2)]
        .where((e) => e.backdropPath != null)
        .toList();
    return pool.isEmpty ? null : pool.first;
  }

  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        tmdb.trending('movie'),
        tmdb.trending('tv'),
      ]);
      _topMovies = results[0];
      _topSeries = results[1];
      notifyListeners();

      await Future.wait(StreamingPlatform.all.map((p) async {
        try {
          _platformTops[p.name] = await tmdb.platformTop(p);
        } catch (_) {
          _platformTops[p.name] = const PlatformTops();
        }
      }));
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadForYou(List<Channel> history) async {
    final seeds = history
        .where((c) => c.type != ContentType.live)
        .take(3)
        .toList();
    final signature = seeds.map((c) => c.id).join('|');
    if (signature == _forYouSignature) return;
    _forYouSignature = signature;
    if (seeds.isEmpty) {
      _forYou = [];
      _forYouSource = null;
      notifyListeners();
      return;
    }
    try {
      final matches = await Future.wait(seeds.map((c) => tmdb
          .findByTitle(c.name, isMovie: c.type == ContentType.movie)
          .catchError((_) => null)));
      final found = matches.whereType<TmdbItem>().toList();
      if (found.isEmpty) return;
      final recs = await Future.wait(found.map((m) => tmdb
          .recommendations(m)
          .catchError((_) => <TmdbItem>[])));
      final seen = found.map((e) => e.key).toSet();
      final merged = <TmdbItem>[];
      for (var i = 0; i < 20; i++) {
        for (final list in recs) {
          if (i < list.length && seen.add(list[i].key)) merged.add(list[i]);
        }
      }
      _forYou = merged.take(20).toList();
      _forYouSource = found.first.title;
      notifyListeners();
    } catch (_) {
      _forYouSignature = '';
    }
  }
}
