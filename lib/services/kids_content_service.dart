import 'foreground_http_client.dart';
import 'playback_work_policy.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/supabase_config.dart';
import '../models/channel.dart';
import '../models/content_type.dart';
import 'kids_policy.dart';
import 'catalog_work_queue.dart';
import 'title_facet_index.dart';

final _foregroundHttp = ForegroundHttpClient();

/// Strict genre/category + age policy. Unknown titles stay hidden except
/// explicitly labelled Animation/Kids groups; known safety vetoes win.
class KidsContentService {
  KidsContentService() {
    PlaybackWorkPolicy.instance.addListener(_resume);
  }
  bool _resumePending = false;
  void _resume() {
    if (_running && !PlaybackWorkPolicy.instance.blocksGuide)
      _resumePending = true;
    if (!_running &&
        _work.pending.isNotEmpty &&
        !PlaybackWorkPolicy.instance.blocksGuide)
      unawaited(_run());
  }

  void dispose() {
    PlaybackWorkPolicy.instance.removeListener(_resume);
    _saveTimer?.cancel();
  }

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
  final Map<String, String> _certifications = {};

  /// TMDB genre ids per title, filled by the same background scan.
  final Map<String, List<int>> _genres = {};
  final CatalogWorkQueue _work = CatalogWorkQueue();
  bool _loaded = false;
  Future<void>? _loading;
  bool _running = false;
  void Function()? onVerdicts;

  /// Normalized keys are computed once per channel object: the kids filter
  /// and the genre bars call this for every title of big playlists.
  static final Expando<String> _keys = Expando('kidsKey');
  static final _nonWord = RegExp(r'[^a-z0-9à-ÿ]+');

  static String keyOf(Channel c) {
    final cached = _keys[c];
    if (cached != null) return cached;
    final type = c.type == ContentType.movie ? 'movie' : 'tv';
    final title = (c.seriesName?.isNotEmpty == true ? c.seriesName! : c.name);
    final norm = title.toLowerCase().replaceAll(_nonWord, ' ').trim();
    return _keys[c] = '$type:$norm';
  }

  static String _titleOf(Channel c) =>
      c.seriesName?.isNotEmpty == true ? c.seriesName! : c.name;

  Future<File> _file() async => File(
    '${(await getApplicationSupportDirectory()).path}/stellartv_kids_v3.json',
  );

  Future<void> load() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    // Verdicts live in a file decoded in a background isolate. They used to
    // be huge strings in the preferences, which slowed every app start and
    // were rewritten on the main thread after each small batch.
    try {
      final file = await _file();
      final path = file.path;
      final data = await Isolate.run(() => _readStore(path));
      _verdicts.addAll(data.verdicts);
      _genres.addAll(data.genres);
      _certifications.addAll(data.certifications);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawGenres = prefs.getString(_genresKey);
      final raw = prefs.getString(_cacheKey);
      if (raw != null || rawGenres != null) {
        final legacy = await Isolate.run(() => _decodeLegacy(raw, rawGenres));
        // Old rating-only approvals must never authorize the strict policy.
        legacy.genres.forEach((k, v) => _genres.putIfAbsent(k, () => v));
        await _persist();
        await prefs.remove(_cacheKey);
        await prefs.remove(_genresKey);
      }
    } catch (_) {}
    // Refresh lists/genre bar right away with the saved data.
    await TitleFacetIndex.instance.load();
    TitleFacetIndex.instance.importGenres(_genres);
    _loaded = true;
    if (_verdicts.isNotEmpty || _genres.isNotEmpty) onVerdicts?.call();
  }

  /// True when the item can be shown in a kids profile.
  static final Expando<bool> _banned = Expando('kidsBanned');

  bool isKidsContent(Channel item) {
    final banned = _banned[item] ??= bannedKeywords.hasMatch(
      '${item.name} ${item.group} ${item.seriesName ?? ''} ${item.plot ?? ''}',
    );
    if (banned) return false;
    final key = keyOf(item);
    final genres =
        TitleFacetIndex.instance.genresOf(key) ?? _genres[key] ?? const <int>[];
    if (!KidsPolicy.allows(
      category: item.group,
      genres: genres,
      certification: _certifications[key] ?? '',
    )) {
      return false;
    }
    // Known cloud vetoes (matched title, overview, rating) always win.
    if (_verdicts[key] == false) return false;
    return true;
  }

  bool isKnown(Channel item) => _verdicts.containsKey(keyOf(item));

  /// TMDB genre ids of a movie/series, or null while not yet checked.
  List<int>? genresOf(Channel item) {
    final key = keyOf(item);
    return TitleFacetIndex.instance.genresOf(key) ?? _genres[key];
  }

  /// Starts filling the shared/local cache as soon as a playlist is loaded,
  /// without requiring the kids profile or the player to be open.
  Future<void> warmUp(Iterable<Channel> items) async {
    await load();
    request(items);
  }

  /// Queues unknown titles and checks them in the background.
  void request(Iterable<Channel> items) {
    for (final c in items) {
      if (c.type != ContentType.movie &&
          c.type != ContentType.series &&
          c.type != ContentType.anime) {
        continue;
      }
      final key = keyOf(c);
      if (_verdicts.containsKey(key) &&
          _certifications.containsKey(key) &&
          TitleFacetIndex.instance.genresFresh(key)) {
        continue;
      }
      _work.add(
        key,
        '${key.split(':').first}\u0000${_titleOf(c)}',
        DateTime.now(),
      );
    }
    if (!_running) unawaited(_run());
  }

  /// Bulk-reads titles already classified in the cloud (shared by every
  /// device and profile), so only truly new titles hit the slow check.
  /// False when the shared cache could not be read: the slow per-title
  /// check then waits for the next scan instead of flooding the server.
  Future<bool> _cloudLookup() async {
    final keys = Map<String, String>.from(_work.pending);
    final all = keys.keys.toList();
    var changed = false;
    for (var i = 0; i < all.length; i += 1000) {
      if (PlaybackWorkPolicy.instance.blocksGuide) return false;
      final chunk = all.sublist(
        i,
        i + 1000 > all.length ? all.length : i + 1000,
      );
      try {
        final res = await _foregroundHttp
            .post(
              Uri.parse('${SupabaseConfig.apiBase}/kids-lookup'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'keys': chunk}),
            )
            .timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) return false;
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        for (final r in (body['results'] as List? ?? const [])) {
          if (r is! Map ||
              r['is_kids'] is! bool ||
              r['key'] is! String ||
              r['certification'] is! String) {
            continue;
          }
          final key = r['key'] as String;
          _verdicts[key] = r['is_kids'] as bool;
          _certifications[key] = r['certification'] as String;
          final g = r['genre_ids'];
          _genres[key] = g is List
              ? [for (final n in g) if (n is num) n.toInt()]
              : const [];
          TitleFacetIndex.instance.putGenres(key, _genres[key]!);
          if (keys.containsKey(key)) _work.complete(key);
          changed = true;
        }
      } catch (_) {
        return false;
      }
    }
    if (changed) {
      await _save();
      onVerdicts?.call();
    }
    return true;
  }

  Future<void> _run() async {
    if (_running || PlaybackWorkPolicy.instance.blocksGuide) return;
    _running = true;
    _resumePending = false;
    try {
      if (!await _cloudLookup()) {
        if (PlaybackWorkPolicy.instance.blocksGuide) return;
        final failed = _work.take(_work.pending.length);
        _work.release(failed.keys, {}, DateTime.now());
        return;
      }
      while (_work.pending.isNotEmpty &&
          !PlaybackWorkPolicy.instance.blocksGuide) {
        final work = _work.take(_batchSize);
        final batch = work.values.toList();
        final resolved = <String>{};
        final items = [
          for (final b in batch)
            {'type': b.split('\u0000').first, 'title': b.split('\u0000').last},
        ];
        try {
          final res = await _foregroundHttp
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
            if (r is! Map ||
                r['is_kids'] is! bool ||
                r['certification'] is! String) {
              continue;
            }
            final norm = (r['title'] as String)
                .toLowerCase()
                .replaceAll(_nonWord, ' ')
                .trim();
            final key = '${r['type']}:$norm';
            _verdicts[key] = r['is_kids'] as bool;
            _certifications[key] = r['certification'] as String;
            final g = r['genre_ids'];
            _genres[key] = g is List
                ? [for (final n in g) if (n is num) n.toInt()]
                : const [];
            TitleFacetIndex.instance.putGenres(key, _genres[key]!);
            resolved.add(key);
          }
          await _save();
          onVerdicts?.call();
        } catch (_) {
          await Future<void>.delayed(const Duration(seconds: 20));
        } finally {
          _work.release(work.keys, resolved, DateTime.now());
          if (PlaybackWorkPolicy.instance.blocksGuide) {
            for (final e in work.entries) {
              if (!resolved.contains(e.key))
                _work.pending.putIfAbsent(e.key, () => e.value);
            }
          }
        }
      }
    } finally {
      _running = false;
      if (_resumePending) {
        _resumePending = false;
        _resume();
      }
    }
  }

  Timer? _saveTimer;

  /// Batched disk write: at most once every 20 seconds.
  Future<void> _save() async {
    if (_saveTimer?.isActive ?? false) return;
    _saveTimer = Timer(const Duration(seconds: 20), () {
      unawaited(_persist());
    });
  }

  Future<void> _persist() async {
    try {
      final file = await _file();
      final path = file.path;
      final verdicts = Map<String, bool>.of(_verdicts);
      final genres = Map<String, List<int>>.of(_genres);
      final certifications = Map<String, String>.of(_certifications);
      await Isolate.run(
        () => _writeStore(path, verdicts, genres, certifications),
      );
    } catch (_) {}
  }
}

class _KidsStore {
  final Map<String, bool> verdicts;
  final Map<String, List<int>> genres;
  final Map<String, String> certifications;
  const _KidsStore(
    this.verdicts,
    this.genres, [
    this.certifications = const {},
  ]);
}

_KidsStore _readStore(String path) {
  final file = File(path);
  if (!file.existsSync()) return const _KidsStore({}, {});
  try {
    final map = jsonDecode(file.readAsStringSync());
    if (map is! Map) return const _KidsStore({}, {});
    final verdicts = <String, bool>{};
    final genres = <String, List<int>>{};
    final v = map['v'];
    if (v is Map) {
      v.forEach((k, value) {
        if (k is String && value is bool) verdicts[k] = value;
      });
    }
    final g = map['g'];
    if (g is Map) {
      g.forEach((k, value) {
        if (k is String && value is List) {
          genres[k] = value.whereType<int>().toList();
        }
      });
    }
    final certifications = <String, String>{};
    final c = map['c'];
    if (c is Map) {
      c.forEach((k, v) {
        if (k is String && v is String) certifications[k] = v;
      });
    }
    return _KidsStore(verdicts, genres, certifications);
  } catch (_) {
    return const _KidsStore({}, {});
  }
}

_KidsStore _decodeLegacy(String? rawVerdicts, String? rawGenres) {
  final verdicts = <String, bool>{};
  final genres = <String, List<int>>{};
  try {
    if (rawVerdicts != null) {
      (jsonDecode(rawVerdicts) as Map<String, dynamic>).forEach((k, v) {
        if (v is bool) verdicts[k] = v;
      });
    }
  } catch (_) {}
  try {
    if (rawGenres != null) {
      (jsonDecode(rawGenres) as Map<String, dynamic>).forEach((k, v) {
        if (v is List) genres[k] = v.whereType<int>().toList();
      });
    }
  } catch (_) {}
  return _KidsStore(verdicts, genres);
}

void _writeStore(
  String path,
  Map<String, bool> verdicts,
  Map<String, List<int>> genres,
  Map<String, String> certifications,
) {
  final temporary = File('$path.tmp');
  temporary.writeAsStringSync(
    jsonEncode({'v': verdicts, 'g': genres, 'c': certifications}),
    flush: true,
  );
  temporary.renameSync(path);
}
