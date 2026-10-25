import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/content_type.dart';
import 'catalog_sort.dart';
import 'title_metadata_store.dart';

/// One compact row of title metadata kept in memory.
class _Facet {
  double imdb = 0;
  bool imdbKnown = false;
  int imdbAt = 0;
  double tmdb = 0;
  bool tmdbKnown = false;
  int tmdbAt = 0;
  int? tmdbId;
  String? mediaKey;
  String? imdbId;
  List<int>? genres;
  int genresAt = 0;
  List<String>? platforms;
  int platformsAt = 0;
  String? logoUrl;
  bool logoKnown = false;
  int logoExpires = 0;

  void copyImdbFrom(_Facet other) {
    imdb = other.imdb;
    imdbKnown = other.imdbKnown;
    imdbAt = other.imdbAt;
    if (other.imdbId != null) imdbId = other.imdbId;
  }
}

class _Subject {
  const _Subject(this.ids, this.names, this.typeName);
  final List<String> ids;
  final List<String> names;
  final String typeName;
}

/// Local index of per-title metadata. The UI reads this, never the network.
/// Votes stay 30 days, genres 180. Skip times stay in the segment library.
class TitleFacetIndex extends ChangeNotifier {
  TitleFacetIndex._();
  static final instance = TitleFacetIndex._();

  static const imdbTtl = Duration(days: 30);
  static const tmdbTtl = Duration(days: 30);
  static const genreTtl = Duration(days: 180);
  static const _fileName = 'title_facets_v1.json';

  final Map<String, _Facet> _rows = {};
  final Map<String, Set<String>> _titleKeysByMedia = {};
  final Map<ContentType, _Subject> _subjects = {};
  final Map<ContentType, List<String>> _ranked = {};
  final Map<ContentType, int> _generations = {};
  final Map<ContentType, int> _jobs = {};
  Future<void>? _loading;
  Timer? _saveTimer;
  Timer? _notifyTimer;
  Timer? _rankTimer;
  bool _rankPending = false;
  int _bulk = 0;
  bool _dirty = false;

  int _now() => DateTime.now().millisecondsSinceEpoch;

  _Facet _row(String key) => _rows.putIfAbsent(key, _Facet.new);

  /// IMDb score for `movie:{id}` or `tv:{id}`. Null while unknown.
  /// Zero means a finished lookup found no IMDb score.
  double? imdbOfMedia(String mediaKey) {
    final row = _rows[mediaKey];
    if (row == null || !row.imdbKnown) return null;
    return row.imdb;
  }

  bool imdbFresh(String mediaKey) {
    final row = _rows[mediaKey];
    if (row == null || !row.imdbKnown || row.imdbAt == 0) return false;
    return _now() - row.imdbAt < imdbTtl.inMilliseconds;
  }

  /// IMDb id already resolved for this key, when the index has one.
  String? imdbIdOf(String key) {
    final id = _rows[key]?.imdbId;
    if (id == null || !RegExp(r'^tt\d+$').hasMatch(id)) return null;
    return id;
  }

  /// TMDB id already joined to a catalog title.
  ({int tmdbId, String mediaKey})? linkOf(String titleKey) {
    final row = _rows[titleKey];
    final id = row?.tmdbId;
    final media = row?.mediaKey;
    if (row == null || id == null || media == null) return null;
    return (tmdbId: id, mediaKey: media);
  }

  void putImdbId(String key, String imdbId, {bool quiet = false}) {
    if (key.isEmpty || !RegExp(r'^tt\d+$').hasMatch(imdbId)) return;
    final row = _row(key);
    if (row.imdbId == imdbId) return;
    row.imdbId = imdbId;
    if (key.split(':').length == 2) {
      for (final titleKey in _titleKeysByMedia[key] ?? const <String>{}) {
        _row(titleKey).imdbId = imdbId;
      }
    }
    if (quiet) {
      _dirty = true;
    } else {
      _touch(rank: false);
    }
  }

  List<String>? platformsOf(String mediaKey) => _rows[mediaKey]?.platforms;

  bool platformsFresh(String mediaKey) {
    final row = _rows[mediaKey];
    if (row == null || row.platforms == null || row.platformsAt == 0) {
      return false;
    }
    return _now() - row.platformsAt < tmdbTtl.inMilliseconds;
  }

  void putPlatforms(
    String mediaKey,
    List<String> names, {
    int? at,
    bool quiet = false,
  }) {
    if (mediaKey.split(':').length != 2) return;
    final row = _row(mediaKey);
    final stamp = at ?? _now();
    if (row.platforms != null && row.platformsAt > stamp) return;
    row.platforms = List<String>.from(names);
    row.platformsAt = stamp;
    if (quiet) {
      _dirty = true;
    } else {
      _touch(rank: false);
    }
  }

  void importPlatforms(Map<String, (List<String>, int)> rows) {
    rows.forEach((key, value) {
      putPlatforms(key, value.$1, at: value.$2, quiet: true);
    });
  }

  /// A logo already resolved. Null means the index has no fresh answer.
  /// [url] inside the record is null when a lookup confirmed there is none.
  ({String? url})? logoOf(String mediaKey) {
    final row = _rows[mediaKey];
    if (row == null || !row.logoKnown || row.logoExpires <= _now()) return null;
    return (url: row.logoUrl);
  }

  void putLogo(
    String mediaKey,
    String? url, {
    int? expiresAt,
    bool quiet = false,
  }) {
    if (mediaKey.split(':').length != 2) return;
    if (url != null && !url.startsWith('https://image.tmdb.org/t/p/')) return;
    final row = _row(mediaKey);
    final expires =
        expiresAt ??
        _now() +
            (url == null
                ? const Duration(hours: 6).inMilliseconds
                : const Duration(days: 30).inMilliseconds);
    if (row.logoKnown && row.logoUrl == url && row.logoExpires >= expires) {
      return;
    }
    row.logoKnown = true;
    row.logoUrl = url;
    row.logoExpires = expires;
    if (quiet) {
      _dirty = true;
    } else {
      _touch(rank: false);
    }
  }

  bool tmdbFresh(String titleKey) {
    final row = _rows[titleKey];
    if (row == null || !row.tmdbKnown || row.tmdbAt == 0) return false;
    return _now() - row.tmdbAt < tmdbTtl.inMilliseconds;
  }

  List<int>? genresOf(String key) => _rows[key]?.genres;

  bool genresFresh(String key) {
    final row = _rows[key];
    if (row == null || row.genres == null || row.genresAt == 0) return false;
    return _now() - row.genresAt < genreTtl.inMilliseconds;
  }

  /// Sort score for a canonical title key. IMDb wins when it is positive.
  double scoreOfTitle(String titleKey) {
    final row = _rows[titleKey];
    if (row == null) return 0;
    if (row.imdbKnown && row.imdb > 0) return row.imdb;
    if (row.tmdbKnown && row.tmdb > 0) return row.tmdb;
    return 0;
  }

  int generationOf(ContentType type) => _generations[type] ?? 0;

  /// Null until the first join for [type] finishes.
  List<String>? idsFor(ContentType type) => _ranked[type];

  Future<void> load() => _loading ??= _read();

  Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/$_fileName');

  Future<void> _read() async {
    if (TitleMetadataStore.disabled) return;
    try {
      final path = (await _file()).path;
      final raw = await Isolate.run(() => _readFacetFile(path));
      if (raw == null) return;
      beginBulk();
      _mergeDecoded(raw);
      endBulk();
    } catch (_) {}
  }

  void beginBulk() => _bulk++;

  void endBulk() {
    if (_bulk > 0) _bulk--;
    if (_bulk == 0 && _dirty) _touch(rank: true);
  }

  void mergeImdb(Map<String, (double, int)> rows) {
    rows.forEach((key, value) {
      putImdb(mediaKey: key, rating: value.$1, at: value.$2, quiet: true);
    });
  }

  void putImdb({
    required String mediaKey,
    required double rating,
    String? imdbId,
    int? at,
    bool quiet = false,
  }) {
    if (mediaKey.split(':').length != 2) return;
    final row = _row(mediaKey);
    final stamp = at ?? _now();
    if (row.imdbKnown && row.imdbAt > stamp) return;
    row.imdb = rating;
    row.imdbKnown = true;
    row.imdbAt = stamp;
    if (imdbId != null && RegExp(r'^tt\d+$').hasMatch(imdbId)) {
      row.imdbId = imdbId;
    }
    for (final titleKey in _titleKeysByMedia[mediaKey] ?? const <String>{}) {
      _row(titleKey).copyImdbFrom(row);
    }
    if (quiet) {
      _dirty = true;
    } else {
      _touch(rank: true);
    }
  }

  void putTmdb(String titleKey, double rating, {int? at, bool quiet = false}) {
    final row = _row(titleKey);
    final stamp = at ?? _now();
    if (row.tmdbKnown && row.tmdbAt > stamp) return;
    row.tmdb = rating;
    row.tmdbKnown = true;
    row.tmdbAt = stamp;
    if (quiet) {
      _dirty = true;
    } else {
      _touch(rank: true);
    }
  }

  void link({
    required String titleKey,
    required String mediaKey,
    required int tmdbId,
    double? tmdb,
    int? tmdbAt,
    bool quiet = false,
  }) {
    final row = _row(titleKey);
    row.tmdbId = tmdbId;
    row.mediaKey = mediaKey;
    if (tmdb != null) {
      final stamp = tmdbAt ?? _now();
      if (!row.tmdbKnown || row.tmdbAt <= stamp) {
        row.tmdb = tmdb;
        row.tmdbKnown = true;
        row.tmdbAt = stamp;
      }
    }
    (_titleKeysByMedia[mediaKey] ??= <String>{}).add(titleKey);
    final media = _rows[mediaKey];
    if (media != null && media.imdbKnown) row.copyImdbFrom(media);
    if (quiet) {
      _dirty = true;
    } else if (tmdb != null || (media != null && media.imdbKnown)) {
      _touch(rank: true);
    }
  }

  void putGenres(String key, List<int> genres, {int? at}) {
    final row = _row(key);
    final stamp = at ?? _now();
    if (row.genres != null && row.genresAt > stamp) return;
    row.genres = List<int>.from(genres);
    row.genresAt = stamp;
    _scheduleSave();
  }

  void importGenres(Map<String, List<int>> genres, {int? at}) {
    final stamp = at ?? _now();
    var changed = false;
    genres.forEach((key, value) {
      final row = _row(key);
      if (row.genres != null) return;
      row.genres = List<int>.from(value);
      row.genresAt = stamp;
      changed = true;
    });
    if (changed) _scheduleSave();
  }

  /// Joins the published catalog to the scores already in memory.
  /// Only ids and names cross the isolate.
  Future<void> rank(
    ContentType type,
    List<String> ids,
    List<String> names,
  ) async {
    _subjects[type] = _Subject(
      List<String>.from(ids),
      List<String>.from(names),
      type.name,
    );
    await _runRank(type);
  }

  Map<String, double> _titleScores() {
    final scores = <String, double>{};
    for (final entry in _rows.entries) {
      final row = entry.value;
      final score = row.imdbKnown && row.imdb > 0
          ? row.imdb
          : row.tmdbKnown && row.tmdb > 0
          ? row.tmdb
          : 0.0;
      if (score > 0) scores[entry.key] = score;
    }
    return scores;
  }

  void _scheduleRank() {
    _rankPending = true;
    _rankTimer ??= Timer(const Duration(milliseconds: 300), () {
      _rankTimer = null;
      if (!_rankPending) return;
      _rankPending = false;
      for (final type in _subjects.keys) {
        unawaited(_runRank(type));
      }
    });
  }

  Future<void> _runRank(ContentType type) async {
    final subject = _subjects[type];
    if (subject == null) return;
    final job = (_jobs[type] ?? 0) + 1;
    _jobs[type] = job;
    final ids = subject.ids;
    final names = subject.names;
    final typeName = subject.typeName;
    final scores = _titleScores();
    final ranked = await Isolate.run(
      () => rankKnownTitleIds(ids, names, typeName, scores),
    );
    if (_jobs[type] != job) return;
    _ranked[type] = ranked;
    _generations[type] = (_generations[type] ?? 0) + 1;
    notifyListeners();
  }

  void _touch({required bool rank}) {
    _dirty = true;
    if (rank) _rankPending = true;
    _scheduleSave();
    if (_bulk > 0) return;
    _notifyTimer ??= Timer(const Duration(milliseconds: 50), () {
      _notifyTimer = null;
      if (_rankPending && _subjects.isNotEmpty) {
        _scheduleRank();
      } else {
        _rankPending = false;
      }
      notifyListeners();
    });
  }

  void _scheduleSave() {
    if (TitleMetadataStore.disabled) return;
    _dirty = true;
    _saveTimer ??= Timer(const Duration(seconds: 3), () {
      _saveTimer = null;
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    if (!_dirty || TitleMetadataStore.disabled) return;
    _dirty = false;
    try {
      final path = (await _file()).path;
      final data = <String, Map<String, Object?>>{};
      for (final entry in _rows.entries) {
        final encoded = _encode(entry.value);
        if (encoded.isNotEmpty) data[entry.key] = encoded;
      }
      await Isolate.run(() => _writeFacetFile(path, data));
    } catch (_) {
      _dirty = true;
    }
  }

  void _mergeDecoded(Map<String, Map<String, Object?>> raw) {
    raw.forEach((key, value) {
      final incoming = _decode(value);
      final row = _row(key);
      if (incoming.imdbKnown &&
          (!row.imdbKnown || incoming.imdbAt >= row.imdbAt)) {
        row.copyImdbFrom(incoming);
      }
      if (incoming.tmdbKnown &&
          (!row.tmdbKnown || incoming.tmdbAt >= row.tmdbAt)) {
        row.tmdb = incoming.tmdb;
        row.tmdbKnown = true;
        row.tmdbAt = incoming.tmdbAt;
      }
      if (incoming.tmdbId != null) row.tmdbId = incoming.tmdbId;
      if (incoming.mediaKey != null) row.mediaKey = incoming.mediaKey;
      if (incoming.imdbId != null) row.imdbId = incoming.imdbId;
      if (incoming.genres != null &&
          (row.genres == null || incoming.genresAt >= row.genresAt)) {
        row.genres = incoming.genres;
        row.genresAt = incoming.genresAt;
      }
      if (incoming.platforms != null &&
          (row.platforms == null || incoming.platformsAt >= row.platformsAt)) {
        row.platforms = incoming.platforms;
        row.platformsAt = incoming.platformsAt;
      }
      if (incoming.logoKnown &&
          (!row.logoKnown || incoming.logoExpires >= row.logoExpires)) {
        row.logoKnown = true;
        row.logoUrl = incoming.logoUrl;
        row.logoExpires = incoming.logoExpires;
      }
    });
    _relink();
    _dirty = true;
  }

  void _relink() {
    final snapshot = Map<String, _Facet>.from(_rows);
    _titleKeysByMedia.clear();
    for (final entry in snapshot.entries) {
      final media = entry.value.mediaKey;
      final id = entry.value.tmdbId;
      if (media == null || id == null) continue;
      (_titleKeysByMedia[media] ??= <String>{}).add(entry.key);
      final mediaRow = _row(media);
      if (entry.value.imdbKnown &&
          (!mediaRow.imdbKnown || entry.value.imdbAt >= mediaRow.imdbAt)) {
        mediaRow.copyImdbFrom(entry.value);
      } else if (mediaRow.imdbKnown) {
        entry.value.copyImdbFrom(mediaRow);
      }
      if (entry.value.imdbId != null && mediaRow.imdbId == null) {
        mediaRow.imdbId = entry.value.imdbId;
      }
    }
  }
}

Map<String, Object?> _encode(_Facet row) => {
  if (row.imdbKnown) 'i': row.imdb,
  if (row.imdbAt != 0) 'ia': row.imdbAt,
  if (row.tmdbKnown) 't': row.tmdb,
  if (row.tmdbAt != 0) 'ta': row.tmdbAt,
  if (row.tmdbId != null) 'id': row.tmdbId,
  if (row.mediaKey != null) 'mk': row.mediaKey,
  if (row.imdbId != null) 'tt': row.imdbId,
  if (row.genres != null) 'g': row.genres,
  if (row.genresAt != 0) 'ga': row.genresAt,
  if (row.platforms != null) 'p': row.platforms,
  if (row.platformsAt != 0) 'pa': row.platformsAt,
  if (row.logoKnown) 'l': row.logoUrl,
  if (row.logoExpires != 0) 'le': row.logoExpires,
};

_Facet _decode(Map<String, Object?> raw) {
  final row = _Facet();
  if (raw['i'] is num) {
    row.imdb = (raw['i'] as num).toDouble();
    row.imdbKnown = true;
  }
  if (raw['ia'] is num) row.imdbAt = (raw['ia'] as num).toInt();
  if (raw['t'] is num) {
    row.tmdb = (raw['t'] as num).toDouble();
    row.tmdbKnown = true;
  }
  if (raw['ta'] is num) row.tmdbAt = (raw['ta'] as num).toInt();
  if (raw['id'] is num) row.tmdbId = (raw['id'] as num).toInt();
  if (raw['mk'] is String) row.mediaKey = raw['mk'] as String;
  if (raw['tt'] is String && RegExp(r'^tt\d+$').hasMatch(raw['tt'] as String)) {
    row.imdbId = raw['tt'] as String;
  }
  final genres = raw['g'];
  if (genres is List) {
    row.genres = [for (final n in genres) if (n is num) n.toInt()];
  }
  if (raw['ga'] is num) row.genresAt = (raw['ga'] as num).toInt();
  final platforms = raw['p'];
  if (platforms is List) {
    row.platforms = [for (final name in platforms) if (name is String) name];
  }
  if (raw['pa'] is num) row.platformsAt = (raw['pa'] as num).toInt();
  if (raw.containsKey('l')) {
    final url = raw['l'];
    if (url == null ||
        (url is String && url.startsWith('https://image.tmdb.org/t/p/'))) {
      row.logoKnown = true;
      row.logoUrl = url as String?;
    }
  }
  if (raw['le'] is num) row.logoExpires = (raw['le'] as num).toInt();
  return row;
}

Map<String, Map<String, Object?>>? _readFacetFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final raw = jsonDecode(file.readAsStringSync());
  if (raw is! Map) return null;
  final out = <String, Map<String, Object?>>{};
  raw.forEach((key, value) {
    if (value is Map) {
      out['$key'] = value.map((k, v) => MapEntry('$k', v));
    }
  });
  return out;
}

void _writeFacetFile(String path, Map<String, Map<String, Object?>> data) {
  final tmp = File('$path.tmp');
  tmp.writeAsStringSync(jsonEncode(data), flush: true);
  tmp.renameSync(path);
}
