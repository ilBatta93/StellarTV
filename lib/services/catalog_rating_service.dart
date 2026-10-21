import 'foreground_http_client.dart';
import 'playback_work_policy.dart';

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../config/supabase_config.dart';
import 'tmdb_service.dart';

final _foregroundHttp = ForegroundHttpClient();

/// Shared TV presentation metadata: only two requests in flight, visible
/// posters first, no network work in build, and a persistent device cache.
class CatalogRatingService extends ChangeNotifier {
  CatalogRatingService._() {
    PlaybackWorkPolicy.instance.addListener(_resume);
  }
  void _resume() {
    if (!PlaybackWorkPolicy.instance.blocksGuide) _drain();
  }

  static final instance = CatalogRatingService._();
  final _tmdb = TmdbService();
  final Map<String, double> _ratings = {};
  final LinkedHashMap<String, Channel> _queue = LinkedHashMap();
  final Set<String> _active = {};
  final Map<String, DateTime> _failed = {};
  Future<void>? _loading;
  Timer? _saveTimer;
  Timer? _notifyTimer;
  int version = 0;

  /// Batches UI updates: a large catalog can resolve hundreds of ratings, and
  /// notifying per result forced a full re-sort/rebuild for each one.
  void _scheduleNotify() {
    _notifyTimer ??= Timer(const Duration(milliseconds: 2500), () {
      _notifyTimer = null;
      version++;
      notifyListeners();
    });
  }

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

  static const _batch = 40;
  bool _cloudDown = false;
  DateTime? _cloudDownAt;

  /// Up to two requests in flight, each resolving a group of 40 titles from
  /// the shared cloud cache (direct TMDB only if the cloud is unreachable).
  void _drain({bool priority = false}) {
    if (PlaybackWorkPolicy.instance.blocksGuide) return;
    if (_cloudDown &&
        _cloudDownAt != null &&
        DateTime.now().difference(_cloudDownAt!).inMinutes >= 5) {
      _cloudDown = false;
    }
    while (_active.length < (_cloudDown ? 2 : 2 * _batch) &&
        _queue.isNotEmpty) {
      if (_cloudDown) {
        final key = priority ? _queue.keys.last : _queue.keys.first;
        final channel = _queue.remove(key);
        if (channel == null) continue;
        _active.add(key);
        unawaited(_fetch(key, channel));
        continue;
      }
      final keys = (priority ? _queue.keys.toList().reversed : _queue.keys)
          .take(_batch)
          .toList();
      final group = <String, Channel>{};
      for (final k in keys) {
        final c = _queue.remove(k);
        if (c != null) group[k] = c;
      }
      _active.addAll(group.keys);
      unawaited(_fetchGroup(group));
    }
  }

  Future<void> _fetchGroup(Map<String, Channel> group) async {
    final entries = group.entries.toList();
    try {
      final res = await _foregroundHttp
          .post(
            Uri.parse('${SupabaseConfig.apiBase}/ratings'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'items': [
                for (final e in entries)
                  {
                    'title': e.value.displaySeriesName,
                    'type': e.value.type == ContentType.movie ? 'movie' : 'tv',
                  },
              ],
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) throw Exception('ratings ${res.statusCode}');
      final list = (jsonDecode(res.body) as Map)['results'] as List;
      for (var i = 0; i < entries.length && i < list.length; i++) {
        final v = list[i];
        if (v is num) {
          _ratings[entries[i].key] = v.toDouble();
        } else {
          _failed[entries[i].key] = DateTime.now();
        }
      }
      _scheduleNotify();
      _saveTimer ??= Timer(const Duration(seconds: 10), () {
        _saveTimer = null;
        unawaited(_save());
      });
    } catch (_) {
      // Cloud unreachable: put the titles back and use direct TMDB lookups.
      if (!PlaybackWorkPolicy.instance.blocksGuide) {
        _cloudDown = true;
        _cloudDownAt = DateTime.now();
      }
      for (final e in entries) {
        _queue[e.key] = e.value;
      }
    } finally {
      _active.removeAll(group.keys);
      _drain();
    }
  }

  Future<void> _fetch(String key, Channel c) async {
    try {
      final item = await _tmdb.findByTitle(
        c.displaySeriesName,
        isMovie: c.type == ContentType.movie,
      );
      if (item == null && PlaybackWorkPolicy.instance.blocksGuide) {
        _queue[key] = c;
        return;
      }
      _ratings[key] = item?.voteAverage ?? 0;
      _scheduleNotify();
      _saveTimer ??= Timer(const Duration(seconds: 10), () {
        _saveTimer = null;
        unawaited(_save());
      });
    } catch (_) {
      if (PlaybackWorkPolicy.instance.blocksGuide) {
        _queue[key] = c;
      } else {
        _failed[key] = DateTime.now();
      }
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
