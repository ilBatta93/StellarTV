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
import 'device_type_service.dart';
import 'tmdb_service.dart';
import 'title_matching.dart';
import 'imdb_rating_service.dart';
import 'title_facet_index.dart';
import 'title_metadata_store.dart';
import 'work_slicer.dart';
import '../models/tmdb_item.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'frame_telemetry_service.dart';
import 'image_warmup_service.dart' show RemoteNavigation;

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
      TitleFacetIndex.instance.putImdbId(ImdbRatingService.keyOf(item), imdbId);
    }
  }

  void remember(Channel c, TmdbItem item) {
    final key = _key(c);
    identities.put(key, item);
    _unprimed.add(item);
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

  /// Four lanes: titles on screen (newest first) before the catalog warm-up,
  /// and the shared cloud cache apart from direct TMDB lookups. A single
  /// queue let one group of 40 year-tagged titles, resolved two at a time,
  /// hold the posters on screen for minutes.
  final LinkedHashMap<String, Channel> _cloudFront = LinkedHashMap();
  final LinkedHashMap<String, Channel> _cloudBack = LinkedHashMap();
  final LinkedHashMap<String, Channel> _directFront = LinkedHashMap();
  final LinkedHashMap<String, Channel> _directBack = LinkedHashMap();
  final Set<String> _active = {};
  int _cloudGroups = 0;
  int _directActive = 0;
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
      final clock = Stopwatch()..start();
      version++;
      notifyListeners();
      _primeImdb();
      FrameTelemetryService.instance.recordWork('voti.notifica', clock);
    });
  }

  /// Shared-cache IMDb scores for identities that are due, never during playback.
  /// Identities stored since the last prime. `prime` never asks a title
  /// twice in a session, so after the first full pass only these need it:
  /// rescanning tens of thousands of identities every 2.5 s took about a
  /// tenth of the TV's UI thread.
  final List<TmdbItem> _unprimed = [];
  bool _primedAll = false;

  void _primeImdb() {
    if (PlaybackWorkPolicy.instance.blocksGuide) return;
    final source = _primedAll ? _unprimed : identities.values;
    final items = <TmdbItem>[];
    for (final item in source) {
      if (!TitleFacetIndex.instance.imdbFresh(ImdbRatingService.keyOf(item))) {
        items.add(item);
      }
    }
    _primedAll = true;
    _unprimed.clear();
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

  /// Queues every title of a published catalog that has no recent score.
  /// Cards only ask for what is on screen, so sorting by score left titles
  /// never scrolled to without a score, at the end of the list.
  /// [names] are display names: their keys are parsed off the UI isolate.
  Future<void> warmTitles(
    ContentType type,
    List<String> ids,
    List<String> names,
  ) async {
    // Only the TV sorts by score; tests never reach the network.
    if (!DeviceTypeService.isTv || TitleMetadataStore.disabled) return;
    if (type != ContentType.movie &&
        type != ContentType.series &&
        type != ContentType.anime) {
      return;
    }
    await ensureLoaded();
    final typeName = type.name;
    // Key and lane are parsed in the isolate: parsing tens of thousands of
    // names here held the TV's UI thread for seconds after every publish.
    final parsed = await Isolate.run(
      () => [
        for (final name in names)
          (parseTitle(name).key(typeName), needsDirectLookup(name)),
      ],
    );
    final missing = <Channel>[];
    final seen = <String>{};
    final slice = WorkSlicer();
    for (var i = 0; i < parsed.length && i < ids.length; i++) {
      await slice.pause();
      final (key, direct) = parsed[i];
      if (names[i].isEmpty || !seen.add(key)) continue;
      if (TitleFacetIndex.instance.tmdbFresh(key)) continue;
      final stub = Channel(
        id: ids[i],
        name: names[i],
        url: '',
        logo: '',
        group: '',
        type: type,
      );
      _keys[stub] = key;
      _direct[stub] = direct;
      missing.add(stub);
    }
    if (missing.isNotEmpty) warm(missing);
  }

  final Expando<String> _keys = Expando('tvRating');
  final Expando<bool> _direct = Expando('tvRatingLane');

  /// Keys looked up during this run, found or not. A poster without a TMDB
  /// match asked again at every rebuild.
  final Set<String> _done = {};

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
      // In slices with a frame between them: one pass over every saved
      // score and identity held the TV's UI thread for seconds at start.
      try {
        await index.mergeImdbStore(
          ImdbRatingService.instance.store.timedSnapshot,
        );
        final slice = WorkSlicer();
        for (final entry in data.entries) {
          index.putTmdb(entry.key, entry.value, at: stamp, quiet: true);
          await slice.pause();
        }
        for (final entry in identities.timedSnapshot().entries) {
          index.link(
            titleKey: entry.key,
            mediaKey: ImdbRatingService.keyOf(entry.value.$1),
            tmdbId: entry.value.$1.id,
            tmdb: data[entry.key],
            tmdbAt: data.containsKey(entry.key) ? stamp : null,
            quiet: true,
          );
          await slice.pause();
        }
      } finally {
        index.endBulk();
      }
      version++;
      notifyListeners();
      // Stored identities are now in memory: one full pass covers them.
      _primedAll = false;
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
    final slice = WorkSlicer();
    for (final c in snapshot) {
      await slice.pause();
      if (c.type != ContentType.movie &&
          c.type != ContentType.series &&
          c.type != ContentType.anime) {
        continue;
      }
      final key = _key(c);
      final failed = _failed[key];
      if ((TitleFacetIndex.instance.tmdbFresh(key) && itemOf(c) != null) ||
          _done.contains(key) ||
          _active.contains(key) ||
          (failed != null && DateTime.now().difference(failed).inMinutes < 5)) {
        continue;
      }
      _enqueue(key, c, front: priority);
    }
    _drain();
  }

  /// Titles with a year skip the shared cache: its key drops the year, so
  /// remakes would share one score.
  @visibleForTesting
  static bool needsDirectLookup(String name) {
    final parsed = parseTitle(name);
    return parsed.year != null || _leadingYear.hasMatch(parsed.title);
  }

  static final _leadingYear = RegExp(r'^(19|20)\d{2}');

  void _enqueue(String key, Channel c, {required bool front}) {
    final direct = _direct[c] ??= needsDirectLookup(c.displaySeriesName);
    final head = direct ? _directFront : _cloudFront;
    final tail = direct ? _directBack : _cloudBack;
    if (front) {
      tail.remove(key);
      head.remove(key);
      head[key] = c;
      // Posters scrolled past long ago go back to the warm-up order.
      while (head.length > _frontLimit) {
        final old = head.keys.first;
        tail[old] = head.remove(old)!;
      }
    } else if (!head.containsKey(key) &&
        (tail.length < 60000 || tail.containsKey(key))) {
      tail[key] = c;
    }
  }

  static const _frontLimit = 240;

  /// Newest on-screen titles first, then the warm-up in catalog order.
  MapEntry<String, Channel>? _take(
    LinkedHashMap<String, Channel> front,
    LinkedHashMap<String, Channel> back,
  ) {
    if (front.isNotEmpty) {
      final key = front.keys.last;
      return MapEntry(key, front.remove(key)!);
    }
    if (back.isNotEmpty) {
      // Background warming waits while the remote moves: its requests and
      // JSON parsing competed with the focus animation on TV boxes.
      if (RemoteNavigation.moving) {
        _resumeAfterRemote();
        return null;
      }
      final key = back.keys.first;
      return MapEntry(key, back.remove(key)!);
    }
    return null;
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

  /// Two cloud groups of 40 titles and up to four direct TMDB lookups in
  /// flight. The warm-up keeps two direct slots free for the screen.
  bool _waitingRemote = false;

  void _resumeAfterRemote() {
    if (_waitingRemote) return;
    _waitingRemote = true;
    unawaited(
      RemoteNavigation.idle().then((_) {
        _waitingRemote = false;
        _drain();
      }),
    );
  }

  void _drain() {
    if (PlaybackWorkPolicy.instance.blocksGuide) return;
    if (_cloudDown &&
        _cloudDownAt != null &&
        DateTime.now().difference(_cloudDownAt!).inMinutes >= 5) {
      _cloudDown = false;
    }
    while (!_cloudDown && _cloudGroups < 2) {
      final group = <String, Channel>{};
      while (group.length < _batch) {
        final next = _take(_cloudFront, _cloudBack);
        if (next == null) break;
        group[next.key] = next.value;
      }
      if (group.isEmpty) break;
      _cloudGroups++;
      _active.addAll(group.keys);
      unawaited(_fetchGroup(group));
    }
    while (_directActive < 4) {
      final onScreen =
          _directFront.isNotEmpty || _cloudDown && _cloudFront.isNotEmpty;
      if (!onScreen && _directActive >= 2) break;
      final next =
          _take(_directFront, _directBack) ??
          (_cloudDown ? _take(_cloudFront, _cloudBack) : null);
      if (next == null) break;
      _directActive++;
      _active.add(next.key);
      unawaited(_fetch(next.key, next.value, direct: true));
    }
  }

  Future<void> _fetchGroup(Map<String, Channel> group) async {
    final entries = group.entries.toList();
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
      final clock = Stopwatch()..start();
      final body = jsonDecode(res.body) as Map;
      final list = body['results'] as List;
      final ids = body['identities'] as List?;
      if (list.length != entries.length ||
          (ids != null && ids.length != entries.length)) {
        throw const FormatException('Misaligned rating response');
      }
      // One rank and one save for the whole group, not one per title.
      TitleFacetIndex.instance.beginBulk();
      try {
        for (var i = 0; i < entries.length && i < list.length; i++) {
          final v = list[i];
          _done.add(entries[i].key);
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
            // No score known: the next catalog warm-up does not ask again.
            TitleFacetIndex.instance.putTmdb(entries[i].key, 0, quiet: true);
          }
        }
      } finally {
        TitleFacetIndex.instance.endBulk();
      }
      FrameTelemetryService.instance.recordWork('voti.gruppo', clock);
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
      _active.removeAll(group.keys);
      for (final e in entries) {
        _enqueue(e.key, e.value, front: false);
      }
    } finally {
      _active.removeAll(group.keys);
      _cloudGroups--;
      _drain();
    }
  }

  Future<void> _fetch(String key, Channel c, {bool direct = false}) async {
    try {
      final item = await _tmdb.findByTitle(
        c.displaySeriesName,
        isMovie: c.type == ContentType.movie,
      );
      if (item == null && PlaybackWorkPolicy.instance.blocksGuide) {
        _active.remove(key);
        _enqueue(key, c, front: false);
        return;
      }
      _done.add(key);
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
        _active.remove(key);
        _enqueue(key, c, front: false);
      } else {
        _failed[key] = DateTime.now();
      }
    } finally {
      _active.remove(key);
      if (direct) _directActive--;
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
