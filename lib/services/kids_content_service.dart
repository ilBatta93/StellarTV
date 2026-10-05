import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/supabase_config.dart';
import '../models/channel.dart';
import '../models/content_type.dart';

/// Kids profile filter based on TMDB age certifications (G, PG, TV-Y,
/// TV-Y7...) checked by the app server, plus a list of banned keywords.
/// Verdicts are cached on the device; unknown titles stay hidden until
/// they are checked.
class KidsContentService {
  static const _cacheKey = 'kids_verdicts_v1';
  static const _genresKey = 'tmdb_genres_v1';
  static const _batchSize = 40;

  static final bannedKeywords = RegExp(
    r'\b(xxx|porn\w*|sex\w*|sesso|eroti\w*|adult[io]?|nud[oi]ty?|horror|'
    r'terror|slasher|gore|zombie\w*|killer|assassin\w*|omicid\w*|murder|'
    r'drug|droga|narcos|gangster|mafia|violen\w*|tortur\w*|satan\w*|'
    r'demon\w*|esorcist\w*|exorcist|vm\s?18|vm\s?14)\b|18\s*\+',
    caseSensitive: false,
  );

  final Map<String, bool> _verdicts = {};

  /// TMDB genre ids per title, filled by the same background scan.
  final Map<String, List<int>> _genres = {};
  final Set<String> _pending = {};
  bool _loaded = false;
  bool _running = false;
  void Function()? onVerdicts;

  static String keyOf(Channel c) {
    final type = c.type == ContentType.movie ? 'movie' : 'tv';
    final title = (c.seriesName?.isNotEmpty == true ? c.seriesName! : c.name);
    final norm = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9à-ÿ]+'), ' ')
        .trim();
    return '$type:$norm';
  }

  static String _titleOf(Channel c) =>
      c.seriesName?.isNotEmpty == true ? c.seriesName! : c.name;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final rawGenres = prefs.getString(_genresKey);
    if (rawGenres != null) {
      try {
        (jsonDecode(rawGenres) as Map<String, dynamic>).forEach((k, v) {
          if (v is List) _genres[k] = v.whereType<int>().toList();
        });
      } catch (_) {}
    }
    final raw = prefs.getString(_cacheKey);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        map.forEach((k, v) {
          if (v is bool) _verdicts[k] = v;
        });
      } catch (_) {}
    }
    // Refresh lists/genre bar right away with the saved data.
    if (_verdicts.isNotEmpty || _genres.isNotEmpty) onVerdicts?.call();
  }

  /// True when the item can be shown in a kids profile.
  bool isKidsContent(Channel item) {
    if (bannedKeywords.hasMatch(
      '${item.name} ${item.seriesName ?? ''} ${item.plot ?? ''}',
    )) {
      return false;
    }
    return _verdicts[keyOf(item)] == true;
  }

  bool isKnown(Channel item) => _verdicts.containsKey(keyOf(item));

  /// TMDB genre ids of a movie/series, or null while not yet checked.
  List<int>? genresOf(Channel item) => _genres[keyOf(item)];

  /// Starts filling the shared/local cache as soon as a playlist is loaded,
  /// without requiring the kids profile or the player to be open.
  Future<void> warmUp(Iterable<Channel> items) async {
    await load();
    request(items);
  }

  /// Queues unknown titles and checks them in the background.
  void request(Iterable<Channel> items) {
    for (final c in items) {
      if (c.type != ContentType.movie && c.type != ContentType.series) continue;
      final key = keyOf(c);
      if (_verdicts.containsKey(key) && _genres.containsKey(key)) continue;
      _pending.add('${key.split(':').first}\u0000${_titleOf(c)}');
    }
    if (!_running) unawaited(_run());
  }

  /// Bulk-reads titles already classified in the cloud (shared by every
  /// device and profile), so only truly new titles hit the slow check.
  Future<void> _cloudLookup() async {
    final keys = <String, String>{};
    for (final b in _pending) {
      final type = b.split('\u0000').first;
      final norm = b
          .split('\u0000')
          .last
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9à-ÿ]+'), ' ')
          .trim();
      keys['$type:$norm'] = b;
    }
    final all = keys.keys.toList();
    var changed = false;
    for (var i = 0; i < all.length; i += 1000) {
      final chunk = all.sublist(
        i,
        i + 1000 > all.length ? all.length : i + 1000,
      );
      try {
        final res = await http
            .post(
              Uri.parse('${SupabaseConfig.apiBase}/kids-lookup'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'keys': chunk}),
            )
            .timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) return;
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        for (final r in (body['results'] as List? ?? const [])) {
          if (r is! Map || r['is_kids'] is! bool || r['key'] is! String)
            continue;
          final key = r['key'] as String;
          _verdicts[key] = r['is_kids'] as bool;
          final g = r['genre_ids'];
          _genres[key] = g is List ? g.whereType<int>().toList() : const [];
          final p = keys[key];
          if (p != null) _pending.remove(p);
          changed = true;
        }
      } catch (_) {
        return;
      }
    }
    if (changed) {
      await _save();
      onVerdicts?.call();
    }
  }

  Future<void> _run() async {
    _running = true;
    try {
      await _cloudLookup();
      while (_pending.isNotEmpty) {
        final batch = _pending.take(_batchSize).toList();
        _pending.removeAll(batch);
        final items = [
          for (final b in batch)
            {'type': b.split('\u0000').first, 'title': b.split('\u0000').last},
        ];
        try {
          final res = await http
              .post(
                Uri.parse('${SupabaseConfig.apiBase}/kids-check'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'items': items}),
              )
              .timeout(const Duration(seconds: 60));
          if (res.statusCode != 200) {
            await Future<void>.delayed(const Duration(seconds: 20));
            continue;
          }
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          for (final r in (body['results'] as List? ?? const [])) {
            if (r is! Map || r['is_kids'] is! bool) continue;
            final norm = (r['title'] as String)
                .toLowerCase()
                .replaceAll(RegExp(r'[^a-z0-9à-ÿ]+'), ' ')
                .trim();
            final key = '${r['type']}:$norm';
            _verdicts[key] = r['is_kids'] as bool;
            final g = r['genre_ids'];
            _genres[key] = g is List ? g.whereType<int>().toList() : const [];
          }
          await _save();
          onVerdicts?.call();
        } catch (_) {
          await Future<void>.delayed(const Duration(seconds: 20));
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(_verdicts));
    await prefs.setString(_genresKey, jsonEncode(_genres));
  }
}
