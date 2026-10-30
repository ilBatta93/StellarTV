import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/channel.dart';
import '../models/content_type.dart';
import 'catalog_rating_service.dart';
import 'foreground_http_client.dart';
import 'title_facet_index.dart';
import 'imdb_resolver.dart';
import 'introdb_service.dart';
import 'playback_assistance.dart';
import 'playback_work_policy.dart';
import 'series_grouping.dart';
import 'title_metadata_store.dart';

/// One saved answer. Empty answers expire sooner so a later publication
/// can still appear. Confirmed times stay on the device for a month.
class SegmentSnapshot {
  final EpisodeSegments segments;
  final int savedAt;
  const SegmentSnapshot(this.segments, this.savedAt);

  bool get fresh {
    final age = DateTime.now().millisecondsSinceEpoch - savedAt;
    final ttl = segments.all.isEmpty
        ? const Duration(days: 2)
        : const Duration(days: 30);
    return age >= 0 && age < ttl.inMilliseconds;
  }

  Map<String, Object?> toJson() => {
    'savedAt': savedAt,
    'segments': [
      for (final s in segments.all)
        {
          'type': s.type,
          'start': s.start.inMilliseconds,
          'end': s.end.inMilliseconds,
        },
    ],
  };

  static SegmentSnapshot? parse(Object? raw) {
    if (raw is! Map) return null;
    final savedAt = raw['savedAt'];
    final list = raw['segments'];
    if (savedAt is! int || list is! List) return null;
    final all = <SkipSegment>[];
    for (final item in list) {
      if (item is! Map) continue;
      final type = '${item['type'] ?? ''}';
      final start = item['start'];
      final end = item['end'];
      if (type.isEmpty || start is! int || end is! int || end <= start) {
        continue;
      }
      all.add(
        SkipSegment(
          type,
          Duration(milliseconds: start),
          Duration(milliseconds: end),
        ),
      );
    }
    SkipSegment? first(Set<String> types) =>
        all.where((s) => types.contains(s.type)).firstOrNull;
    return SegmentSnapshot(
      EpisodeSegments(
        intro: first({'intro'}),
        outro: first({'outro', 'credits'}),
        all: all,
      ),
      savedAt,
    );
  }
}

/// Skip times for the open season, remembered on the device and filled from
/// the shared cache. Playback reads the local copy and asks the network only
/// for the episode that is actually missing.
class SegmentLibrary {
  SegmentLibrary._();
  static final instance = SegmentLibrary._();

  final store = TitleMetadataStore<SegmentSnapshot>(
    fileName: 'skip_segments_v1.json',
    encode: (v) => v.toJson(),
    decode: SegmentSnapshot.parse,
    ttl: const Duration(days: 30),
  );
  final _ids = TitleMetadataStore<String>(
    fileName: 'skip_segment_ids_v1.json',
    encode: (v) => v,
    decode: (raw) =>
        raw is String && RegExp(r'^tt\d+$').hasMatch(raw) ? raw : null,
    ttl: const Duration(days: 30),
  );
  final _http = ForegroundHttpClient();
  final _pending = <String, Future<EpisodeSegments?>>{};

  Future<void> load() async {
    await Future.wait([
      store.load(),
      _ids.load(),
      TitleFacetIndex.instance.load(),
    ]);
    final index = TitleFacetIndex.instance;
    index.beginBulk();
    for (final entry in _ids.timedSnapshot().entries) {
      if (_ids.isFresh(entry.key)) {
        index.putImdbId(entry.key, entry.value.$1, quiet: true);
      }
    }
    index.endBulk();
  }

  /// Visible season, one episode at a time, and never while a video is open.
  Future<void> prepareSeason({
    required int tmdbId,
    required String title,
    required int season,
    required List<int> episodes,
  }) async {
    if (TitleMetadataStore.disabled) return;
    await load();
    if (PlaybackWorkPolicy.instance.blocksGuide) return;
    final imdb = await _imdb(
      tmdbId: tmdbId,
      title: segmentLookupTitle(title),
      movie: false,
    );
    if (imdb == null) return;
    for (final episode in episodes.take(40)) {
      if (episode < 1 || PlaybackWorkPolicy.instance.blocksGuide) return;
      if (_cached(imdb, movie: false, season: season, episode: episode) !=
          null) {
        continue;
      }
      await _resolve(imdb, movie: false, season: season, episode: episode);
    }
  }

  Future<void> prepareMovie({
    required int tmdbId,
    required String title,
  }) async {
    if (TitleMetadataStore.disabled) return;
    await load();
    if (PlaybackWorkPolicy.instance.blocksGuide) return;
    final imdb = await _imdb(
      tmdbId: tmdbId,
      title: segmentLookupTitle(title),
      movie: true,
    );
    if (imdb == null) return;
    if (_cached(imdb, movie: true) != null) return;
    await _resolve(imdb, movie: true);
  }

  /// Local copy first. [onData] runs once, as soon as an answer exists.
  Future<void> deliver(
    Channel channel,
    void Function(EpisodeSegments segments) onData,
  ) async {
    if (TitleMetadataStore.disabled) return;
    final query = _query(channel);
    if (query == null) return;
    await load();
    final imdb = await _imdb(
      tmdbId: query.tmdbId,
      title: query.title,
      movie: query.movie,
    );
    if (imdb == null) return;
    final hit = _cached(
      imdb,
      movie: query.movie,
      season: query.season,
      episode: query.episode,
    );
    if (hit != null) {
      onData(hit);
      return;
    }
    final fresh = await _resolve(
      imdb,
      movie: query.movie,
      season: query.season,
      episode: query.episode,
    );
    if (fresh != null) onData(fresh);
  }

  _Query? _query(Channel channel) {
    final movie = channel.type == ContentType.movie;
    if (!movie &&
        channel.type != ContentType.series &&
        channel.type != ContentType.anime) {
      return null;
    }
    var season = channel.season;
    var episode = channel.episode;
    if (!movie && (season == null || episode == null)) {
      final parsed = SeriesGrouping.parseTitle(channel.name);
      season ??= parsed.season;
      episode ??= parsed.episode;
    }
    if (!movie && (season == null || episode == null)) return null;
    final item = CatalogRatingService.instance.itemOf(channel);
    final matched = item != null && item.isMovie == movie;
    return _Query(
      movie: movie,
      season: season,
      episode: episode,
      tmdbId: matched ? item.id : null,
      title: segmentLookupTitle(
        matched ? item.title : channel.displaySeriesName,
      ),
    );
  }

  Future<String?> _imdb({
    int? tmdbId,
    required String title,
    required bool movie,
  }) async {
    final kind = movie ? 'movie' : 'tv';
    final keys = <String>[
      if (tmdbId != null) '$kind:$tmdbId',
      if (title.isNotEmpty) '$kind:t:${title.toLowerCase()}',
    ];
    for (final key in keys) {
      final known = TitleFacetIndex.instance.imdbIdOf(key);
      if (known != null) return known;
    }
    final id = await ImdbResolver.getImdbId(
      tmdbId: tmdbId,
      title: title.isEmpty ? null : title,
      isMovie: movie,
    );
    if (id == null) return null;
    for (final key in keys) {
      TitleFacetIndex.instance.putImdbId(key, id);
    }
    return id;
  }

  String _storageKey(
    String imdb, {
    required bool movie,
    int? season,
    int? episode,
  }) => movie ? 'movie:$imdb' : '$imdb:$season:$episode';

  EpisodeSegments? _cached(
    String imdb, {
    required bool movie,
    int? season,
    int? episode,
  }) {
    final snap = store.valueOf(
      _storageKey(imdb, movie: movie, season: season, episode: episode),
    );
    if (snap == null || !snap.fresh) return null;
    return snap.segments;
  }

  Future<EpisodeSegments?> _resolve(
    String imdb, {
    required bool movie,
    int? season,
    int? episode,
  }) {
    final key = _storageKey(
      imdb,
      movie: movie,
      season: season,
      episode: episode,
    );
    final saved = _cached(imdb, movie: movie, season: season, episode: episode);
    if (saved != null) return Future.value(saved);
    return _pending.putIfAbsent(key, () async {
      try {
        final body = await _fetch(
          imdb,
          movie: movie,
          season: season,
          episode: episode,
        );
        if (body == null) return null;
        final segments = IntroDbService.parse(body);
        store.put(
          key,
          SegmentSnapshot(segments, DateTime.now().millisecondsSinceEpoch),
        );
        return segments;
      } finally {
        _pending.remove(key);
      }
    });
  }

  Future<Object?> _fetch(
    String imdb, {
    required bool movie,
    int? season,
    int? episode,
  }) async {
    final query = {
      'imdb_id': imdb,
      if (movie) 'is_movie': 'true',
      if (!movie && season != null) 'season': '$season',
      if (!movie && episode != null) 'episode': '$episode',
    };
    final shared = await _get(
      Uri.parse('${SupabaseConfig.apiBase}/segments')
          .replace(queryParameters: query),
      headers: _authHeaders(),
    );
    if (shared != null) return shared;
    return _get(
      Uri.parse('https://api.introdb.app/segments')
          .replace(queryParameters: query),
    );
  }

  Map<String, String> _authHeaders() {
    var bearer = SupabaseConfig.anonKey;
    try {
      bearer =
          Supabase.instance.client.auth.currentSession?.accessToken ?? bearer;
    } catch (_) {}
    return {'Authorization': 'Bearer $bearer'};
  }

  Future<Object?> _get(Uri uri, {Map<String, String>? headers}) async {
    try {
      final res = await _http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      return body is Map ? body : null;
    } catch (_) {
      return null;
    }
  }
}

class _Query {
  final bool movie;
  final int? season;
  final int? episode;
  final int? tmdbId;
  final String title;
  const _Query({
    required this.movie,
    required this.season,
    required this.episode,
    required this.tmdbId,
    required this.title,
  });
}
