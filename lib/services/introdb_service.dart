import 'dart:convert';

import 'foreground_http_client.dart';

class SkipSegment {
  final String type;
  final Duration start;
  final Duration end;
  const SkipSegment(this.type, this.start, this.end);

  bool contains(Duration t) => t >= start && t < end;
}

class EpisodeSegments {
  final SkipSegment? intro;
  final SkipSegment? outro;
  final List<SkipSegment> all;
  const EpisodeSegments({this.intro, this.outro, this.all = const []});
  static const empty = EpisodeSegments();
}

/// Intro / recap / credits timestamps from IntroDB (api.introdb.app).
/// Any error, 404 or empty answer returns [EpisodeSegments.empty].
class IntroDbService {
  static final _cache = <String, EpisodeSegments>{};
  static final _pending = <String, Future<EpisodeSegments>>{};
  static final _http = ForegroundHttpClient();
  static Future<EpisodeSegments> fetch(
    String imdbId,
    int season,
    int episode,
  ) async {
    final key = '$imdbId:$season:$episode';
    final saved = _cache[key];
    if (saved != null) return saved;
    final pending = _pending[key];
    if (pending != null) return pending;
    final future = _fetch(imdbId, season, episode);
    _pending[key] = future;
    try {
      final value = await future;
      if (value.all.isNotEmpty) {
        if (_cache.length >= 128) _cache.remove(_cache.keys.first);
        _cache[key] = value;
      }
      return value;
    } finally {
      _pending.remove(key);
    }
  }

  static Future<EpisodeSegments> _fetch(
    String imdbId,
    int season,
    int episode,
  ) async {
    try {
      final uri = Uri.parse('https://api.introdb.app/segments').replace(
        queryParameters: {
          'imdb_id': imdbId,
          'season': '$season',
          'episode': '$episode',
        },
      );
      final res = await _http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return EpisodeSegments.empty;
      return parse(jsonDecode(res.body));
    } catch (_) {
      return EpisodeSegments.empty;
    }
  }

  static SkipSegment? _segment(String type, Object? raw) {
    if (raw is! Map) return null;
    final s =
        raw['start_sec'] ??
        (raw['start_ms'] is num ? raw['start_ms'] / 1000 : null);
    final e =
        raw['end_sec'] ?? (raw['end_ms'] is num ? raw['end_ms'] / 1000 : null);
    if (s is! num ||
        e is! num ||
        !s.isFinite ||
        !e.isFinite ||
        s < 0 ||
        e <= s ||
        e > 86400)
      return null;
    return SkipSegment(
      type,
      Duration(milliseconds: (s * 1000).round()),
      Duration(milliseconds: (e * 1000).round()),
    );
  }

  /// Supports both the object form ({intro, recap, outro}) and an array of
  /// segments with `segment_type`.
  static EpisodeSegments parse(Object? body) {
    final all = <SkipSegment>[];
    void add(String type, Object? raw) {
      final s = _segment(type, raw);
      if (s != null) all.add(s);
    }

    final list = body is List
        ? body
        : (body is Map && body['segments'] is List
              ? body['segments'] as List
              : null);
    if (list != null) {
      for (final r in list) {
        if (r is Map)
          add('${r['segment_type'] ?? r['type'] ?? ''}'.toLowerCase(), r);
      }
    } else if (body is Map) {
      for (final t in ['recap', 'intro', 'outro', 'post_credits']) {
        add(t, body[t]);
      }
    }
    if (all.isEmpty) return EpisodeSegments.empty;
    SkipSegment? first(Set<String> types) =>
        all.where((s) => types.contains(s.type)).firstOrNull;
    return EpisodeSegments(
      intro: first({'intro'}) ?? first({'recap'}),
      outro: first({'outro', 'credits'}),
      all: all,
    );
  }
}
