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
import 'title_matching.dart';
import 'imdb_rating_service.dart';
import 'title_facet_index.dart';
import 'title_metadata_store.dart';
import '../models/tmdb_item.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

final _foregroundHttp = ForegroundHttpClient();

/// Shared TV presentation metadata: only two requests in flight, visible
/// posters first, no network work in build, and a persistent device cache.
class CatalogRatingService extends ChangeNotifier {
  CatalogRatingService._() {
    PlaybackWorkPolicy.instance.addListener(_resume);
  }
  List<Channel> _warmHeld = const [];

  void _resume() {
    if (PlaybackWorkPolicy.instance.blocksGuide) return;
    final held = _warmHeld;
    _warmHeld = const [];
    if (held.isNotEmpty) unawaited(request(held));
    _drain();
  }

  static final instance = CatalogRatingService._();
  final _tmdb = TmdbService();
  final identities = TitleMetadataStore<TmdbItem>(
    fileName: 'catalog_rating_identities_v3.json',
    encode: (v) => v.toJson(),
    decode: (v) =>
        v is Map ? TmdbItem.tryParse(Map<String, dynamic>.from(v)) : null,
  );
  TmdbItem? itemOf(Channel c) => identities.valueOf(_key(c));

  /// TMDB id already joined to this catalog title.
  ({int id, bool movie})? linkedIdentity(Channel c) {
    final link = TitleFacetIndex.instance.linkOf(_key(c));
    if (link == null) return null;
    return (id: link.tmdbId, movie: link.mediaKey.startsWith('movie:'));
  }

  /// IMDb id already stored for this title. No network.
  String? imdbIdOf(Channel c) {
    final key = _key(c);
    final direct = TitleFacetIndex.instance.imdbIdOf(key);
    if (direct != null) return direct;
    final link = TitleFacetIndex.instance.linkOf(key);
    if (link != null) {
      final fromMedia = TitleFacetIndex.instance.imdbIdOf(link.mediaKey);
      if (fromMedia != null) return fromMedia;
    }
    final item = identities.valueOf(key);
    if (item == null) return null;
    return TitleFacetIndex.instance.imdbIdOf(ImdbRatingService.keyOf(item));
  }

  void noteImdbId(Channel c, String imdbId) {
    final key = _key(c);
    TitleFacetIndex.instance.putImdbId(key, imdbId);
    final link = TitleFacetIndex.instance.linkOf(key);
    if (link != null) TitleFacetIndex.instance.putImdbId(link.mediaKey, imdbId);
    final item = identities.valueOf(key);
    if (item != null) {
      TitleFacetIndex.instance.putImdbId(
        ImdbRatingService.keyOf(item),
        imdbId,
      );
    }
  }
  void remember(Channel c, TmdbItem item) {
    final key = _key(c);
    identities.put(key, item);
    TitleFacetIndex.instance.link(
      titleKey: key,
      mediaKey: ImdbRatingService.keyOf(item),
      tmdbId: item.id,
      tmdb: _ratings.containsKey(key)
          ? _ratings[key]
          : item.voteAverage > 0
          ? item.voteAverage
          : null,
    );
  }
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
      _primeImdb();
    });
  }

  /// Shared-cache IMDb scores for identities that are due, never during playback.
  void _primeImdb() {
    if (PlaybackWorkPolicy.instance.blocksGuide) return;
    final items = <TmdbItem>[];
    for (final item in identities.snapshot().values) {
      if (!TitleFacetIndex.instance.imdbFresh(ImdbRatingService.keyOf(item))) {
        items.add(item);
      }
    }
    if (items.isNotEmpty) ImdbRatingService.instance.prime(items);
  }

  /// Fills missing scores for the published catalog while the player is closed.
  void warm(Iterable<Channel> channels) {
    final list = channels.toList(growable: false);
    if (PlaybackWorkPolicy.instance.blocksGuide) {
      _warmHeld = list;
      return;
    }
    unawaited(request(list));
  }

  final Expando<String> _keys = Expando('tvRating');

  String _key(Channel c) =>
      _keys[c] ??= parseTitle(c.displaySeriesName).key(c.type.name);
  double? ratingOf(Channel c) => _ratings[_key(c)];

  /// Title-key tables for the sort isolate. IMDb wins when its score is > 0.
  ({Map<String, double> tmdb, Map<String, String> imdbKeys}) ratingTables() {
    final imdbKeys = <String, String>{};
    for (final entry in identities.snapshot().entries) {
      imdbKeys[entry.key] = ImdbRatingService.keyOf(entry.value);
    }
    return (tmdb: Map<String, double>.of(_ratings), imdbKeys: imdbKeys);
  }

  /// Sort value: IMDb when known (>0), otherwise the TMDB vote.
  double sortRatingOf(Channel c) {
    final scored = TitleFacetIndex.instance.scoreOfTitle(_key(c));
    if (scored > 0) return scored;
    final item = itemOf(c);
    final imdb = item == null
        ? null
        : ImdbRatingService.instance.store.valueOf(
            ImdbRatingService.keyOf(item),
          );
    if (imdb != null && imdb > 0) return imdb;
    return _ratings[_key(c)] ?? 0;
  }

  Future<String> _path() async =>
      '${(await getApplicationSupportDirectory()).path}/tv_ratings_v3.json';

  Future<void> _load() async {
    await Future.wait([
      identities.load(),
      ImdbRatingService.instance.store.load(),
      TitleFacetIndex.instance.load(),
    ]);
    try {
      final path = await _path();
      final file = File(path);
      final stamp = file.existsSync()
          ? file.lastModifiedSync().millisecondsSinceEpoch
          : DateTime.now().millisecondsSinceEpoch;
      final data = await Isolate.run(() {
        final stored = File(path);
        if (!stored.existsSync()) return <String, double>{};
        final map = jsonDecode(stored.readAsStringSync()) as Map;
        return map.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
      });
      _ratings.addAll(data);
      final index = TitleFacetIndex.instance;
      index.beginBulk();
      index.mergeImdb(ImdbRatingService.instance.store.timedSnapshot());
      data.forEach(
        (key, value) => index.putTmdb(key, value, at: stamp, quiet: true),
      );
      for (final entry in identities.timedSnapshot().entries) {
        index.link(
          titleKey: entry.key,
          mediaKey: ImdbRatingService.keyOf(entry.value.$1),
          tmdbId: entry.value.$1.id,
          tmdb: data[entry.key],
          tmdbAt: data.containsKey(entry.key) ? stamp : null,
          quiet: true,
        );
      }
      index.endBulk();
      version++;
      notifyListeners();
      _primeImdb();
    } catch (_) {}
  }

  /// Disk ratings and title identities. Safe to await more than once.
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> request(
    Iterable<Channel> channels, {
    bool priority = false,
  }) async {
    final snapshot = channels.toList(growable: false);
    await ensureLoaded();
    for (final c in snapshot) {
      if (c.type != ContentType.movie &&
          c.type != ContentType.series &&
          c.type != ContentType.anime) {
        continue;
      }
      final key = _key(c);
      final failed = _failed[key];
      if ((TitleFacetIndex.instance.tmdbFresh(key) && itemOf(c) != null) ||
          _active.contains(key) ||
          (failed != null && DateTime.now().difference(failed).inMinutes < 5)) {
        continue;
      }
      if (priority) _queue.remove(key);
      if (_queue.length < 5000 || _queue.containsKey(key)) _queue[key] = c;
    }
    _drain(priority: priority);
  }

  String _bearer() {
    try {
      return Supabase.instance.client.auth.currentSession?.accessToken ??
          SupabaseConfig.anonKey;
    } catch (_) {
      return SupabaseConfig.anonKey;
    }
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
    final direct = entries.where((e) {
      final parsed = parseTitle(e.value.displaySeriesName);
      return parsed.year != null ||
          RegExp(r'^(19|20)\d{2}').hasMatch(parsed.title);
    }).toList();
    if (direct.isNotEmpty) {
      for (var i = 0; i < direct.length; i += 2) {
        await Future.wait(
          direct.skip(i).take(2).map((e) => _fetch(e.key, e.value)),
        );
      }
      final remaining = Map<String, Channel>.from(group)
        ..removeWhere((k, _) => direct.any((e) => e.key == k));
      if (remaining.isNotEmpty) await _fetchGroup(remaining);
      return;
    }
    try {
      final res = await _foregroundHttp
          .post(
            Uri.parse('${SupabaseConfig.apiBase}/ratings'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${_bearer()}',
            },
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
      final body = jsonDecode(res.body) as Map;
      final list = body['results'] as List;
      final ids = body['identities'] as List?;
      if (list.length != entries.length ||
          (ids != null && ids.length != entries.length)) {
        throw const FormatException('Misaligned rating response');
      }
      for (var i = 0; i < entries.length && i < list.length; i++) {
        final v = list[i];
        if (v is num) {
          _ratings[entries[i].key] = v.toDouble();
          TitleFacetIndex.instance.putTmdb(entries[i].key, v.toDouble());
          final identity = ids != null && i < ids.length ? ids[i] : null;
          if (identity is Map && identity['id'] is num) {
            final c = entries[i].value;
            remember(
              c,
              TmdbItem(
                id: (identity['id'] as num).toInt(),
                mediaType: c.type == ContentType.movie ? 'movie' : 'tv',
                title: c.displaySeriesName,
                overview: c.plot ?? '',
                posterPath: identity['poster'] is String
                    ? identity['poster'] as String
                    : null,
                backdropPath: null,
                voteAverage: v.toDouble(),
                popularity: 0,
                releaseDate: '',
              ),
            );
          }
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
      TitleFacetIndex.instance.putTmdb(key, item?.voteAverage ?? 0);
      if (item != null) remember(c, item);
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
