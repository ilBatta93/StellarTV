import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import 'tmdb_service.dart';

/// Shared TV presentation metadata: only two requests in flight, visible
/// posters first, no network work in build, and a persistent device cache.
class CatalogRatingService extends ChangeNotifier {
  CatalogRatingService._();
  static final instance = CatalogRatingService._();
  final _tmdb = TmdbService();
  final Map<String, double> _ratings = {};
  final LinkedHashMap<String, Channel> _queue = LinkedHashMap();
  final Set<String> _active = {};
  final Map<String, DateTime> _failed = {};
  Future<void>? _loading;
  Timer? _saveTimer;
  int version = 0;
  final Expando<String> _keys = Expando('tvRating');

  String _key(Channel c) => _keys[c] ??=
      '${c.type.name}:${TmdbService.cleanTitle(c.displaySeriesName).toLowerCase()}';
  double? ratingOf(Channel c) => _ratings[_key(c)];

  Future<String> _path() async =>
      '${(await getApplicationSupportDirectory()).path}/tv_ratings_v1.json';

  Future<void> _load() async {
    try {
      final path = await _path();
      final data = await Isolate.run(() {
        final file = File(path);
        if (!file.existsSync()) return <String, double>{};
        final map = jsonDecode(file.readAsStringSync()) as Map;
        return map.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
      });
      _ratings.addAll(data);
      version++;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> request(
    Iterable<Channel> channels, {
    bool priority = false,
  }) async {
    final snapshot = channels.toList(growable: false);
    await (_loading ??= _load());
    for (final c in snapshot) {
      if (c.type != ContentType.movie && c.type != ContentType.series) continue;
      final key = _key(c);
      final failed = _failed[key];
      if (_ratings.containsKey(key) ||
          _active.contains(key) ||
          (failed != null && DateTime.now().difference(failed).inMinutes < 5)) {
        continue;
      }
      if (priority) _queue.remove(key);
      if (_queue.length < 5000 || _queue.containsKey(key)) _queue[key] = c;
    }
    _drain(priority: priority);
  }

  void _drain({bool priority = false}) {
    while (_active.length < 2 && _queue.isNotEmpty) {
      final key = priority ? _queue.keys.last : _queue.keys.first;
      final channel = _queue.remove(key);
      if (channel == null) continue;
      _active.add(key);
      unawaited(_fetch(key, channel));
    }
  }

  Future<void> _fetch(String key, Channel c) async {
    try {
      final item = await _tmdb.findByTitle(
        c.displaySeriesName,
        isMovie: c.type == ContentType.movie,
      );
      _ratings[key] = item?.voteAverage ?? 0;
      version++;
      notifyListeners();
      _saveTimer ??= Timer(const Duration(seconds: 10), () {
        _saveTimer = null;
        unawaited(_save());
      });
    } catch (_) {
      _failed[key] = DateTime.now();
    } finally {
      _active.remove(key);
      _drain();
    }
  }

  Future<void> _save() async {
    try {
      final path = await _path();
      final values = Map<String, double>.of(_ratings);
      await Isolate.run(() {
        final file = File('$path.tmp');
        file.writeAsStringSync(jsonEncode(values));
        file.renameSync(path);
      });
    } catch (_) {}
  }
}
