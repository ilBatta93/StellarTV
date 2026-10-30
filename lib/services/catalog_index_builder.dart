import 'dart:isolate';

import '../models/channel.dart';
import '../models/content_type.dart';
import 'catalog_builder.dart';
import 'series_grouping.dart';
import 'tmdb_service.dart';

/// Result of the off-thread catalog indexing used by the Home.
///
/// Title keys point to entries with compact codes ([kindShift] bits encode
/// the list: 0 movies, 1 series catalog, 2 anime catalog) so only strings
/// and integers travel back from the background isolate for movies.
class CatalogIndexData {
  static const kindShift = 28;
  static const indexMask = (1 << kindShift) - 1;

  final List<Channel> seriesCatalog;
  final List<Channel> animeCatalog;
  final Map<String, List<int>> titles;

  const CatalogIndexData({
    required this.seriesCatalog,
    required this.animeCatalog,
    required this.titles,
  });

  static int code(int kind, int index) => (kind << kindShift) | index;
  static int kindOf(int code) => code >> kindShift;
  static int indexOf(int code) => code & indexMask;
}

/// Pure function, safe to run inside `Isolate.run`: groups the series lists
/// and normalizes every title once, away from the UI thread.
CatalogIndexData buildCatalogIndex(
  List<String> movieNames,
  List<Channel> seriesItems,
  List<Channel> animeItems, {
  (bool, bool) alreadyGrouped = (false, false),
}) {
  final series = alreadyGrouped.$1
      ? seriesItems
      : SeriesGrouping.catalog(seriesItems);
  final anime = alreadyGrouped.$2
      ? animeItems
      : SeriesGrouping.catalog(animeItems);
  final titles = <String, List<int>>{};
  void add(String raw, int code) {
    final key = catalogTitleKey(raw);
    if (key.isEmpty) return;
    (titles[key] ??= <int>[]).add(code);
  }

  for (var i = 0; i < movieNames.length; i++) {
    add(movieNames[i], CatalogIndexData.code(0, i));
  }
  for (final (kind, list) in [(1, series), (2, anime)]) {
    for (var i = 0; i < list.length; i++) {
      final c = list[i];
      final code = CatalogIndexData.code(kind, i);
      add(c.name, code);
      if (c.seriesName != null && c.seriesName != c.name) {
        add(c.seriesName!, code);
      }
    }
  }
  return CatalogIndexData(
    seriesCatalog: series,
    animeCatalog: anime,
    titles: titles,
  );
}

final _langPrefix = RegExp(r'^\s*[a-z]{2,3}\s*[:|\-]\s*');
final _brackets = RegExp(r'\[[^\]]*\]|\([^)]*\)');
final _nonWord = RegExp(r'[^a-z0-9à-ÿ]+');

/// Title key shared by the playlist index and the TMDB lookups.
String catalogTitleKey(String raw) =>
    TmdbService.cleanTitle(raw)
        .toLowerCase()
        .replaceAll(_langPrefix, '')
        .replaceAll(_brackets, ' ')
        .replaceAll(_nonWord, ' ')
        .trim();

/// One slice of a catalog snapshot. Only the fields the search needs travel
/// to the background isolate: playback addresses stay on the UI heap.
class CatalogSearchChunk {
  final int epoch;
  final List<String> names;
  final List<String> groups;
  final List<String> seriesNames;
  final List<String> seriesKeys;
  final List<String> ids;
  final List<int> types;
  final List<int> seasons;
  final List<int> episodes;
  final List<bool> folders;

  const CatalogSearchChunk({
    required this.epoch,
    required this.names,
    required this.groups,
    required this.seriesNames,
    required this.seriesKeys,
    required this.ids,
    required this.types,
    required this.seasons,
    required this.episodes,
    required this.folders,
  });
}

class CatalogSearchReset {
  const CatalogSearchReset(this.epoch);
  final int epoch;
}

class CatalogSearchCommit {
  const CatalogSearchCommit(this.epoch);
  final int epoch;
}

class CatalogSearchQuery {
  const CatalogSearchQuery(this.id, this.epoch, this.query);
  final int id;
  final int epoch;
  final String query;
}

class CatalogSearchReady {
  const CatalogSearchReady(this.epoch);
  final int epoch;
}

/// Snapshot indexes for direct titles, and folder ids for series and anime.
class CatalogSearchAnswer {
  final int id;
  final int epoch;
  final bool stale;
  final List<int> live;
  final List<int> movie;
  final List<String> seriesIds;
  final List<String> animeIds;

  const CatalogSearchAnswer({
    required this.id,
    required this.epoch,
    required this.stale,
    required this.live,
    required this.movie,
    required this.seriesIds,
    required this.animeIds,
  });

  static CatalogSearchAnswer empty(int id, int epoch, {bool stale = false}) =>
      CatalogSearchAnswer(
        id: id,
        epoch: epoch,
        stale: stale,
        live: const [],
        movie: const [],
        seriesIds: const [],
        animeIds: const [],
      );
}

class _SearchFolder {
  const _SearchFolder(this.id, this.nameLower, this.groupLower, this.seriesKey);
  final String id;
  final String nameLower;
  final String groupLower;
  final String seriesKey;
}

class _SearchMemory {
  final names = <String>[];
  final groups = <String>[];
  final seriesNames = <String>[];
  final seriesKeys = <String>[];
  final ids = <String>[];
  final types = <int>[];
  final seasons = <int>[];
  final episodes = <int>[];
  final folders = <bool>[];
  var seriesFolders = const <_SearchFolder>[];
  var animeFolders = const <_SearchFolder>[];

  void clear() {
    names.clear();
    groups.clear();
    seriesNames.clear();
    seriesKeys.clear();
    ids.clear();
    types.clear();
    seasons.clear();
    episodes.clear();
    folders.clear();
    seriesFolders = const [];
    animeFolders = const [];
  }

  void add(CatalogSearchChunk chunk) {
    final count = chunk.names.length;
    for (var i = 0; i < count; i++) {
      names.add(chunk.names[i].toLowerCase());
      groups.add(chunk.groups[i].toLowerCase());
      seriesNames.add(chunk.seriesNames[i].trim().toLowerCase());
      seriesKeys.add(chunk.seriesKeys[i]);
      ids.add(chunk.ids[i]);
      types.add(chunk.types[i]);
      seasons.add(chunk.seasons[i]);
      episodes.add(chunk.episodes[i]);
      folders.add(chunk.folders[i]);
    }
  }

  /// Folder identity follows the same rules as the visible series list:
  /// existing folders win, otherwise one folder per series key.
  void rebuildFolders() {
    seriesFolders = _foldersFor(ContentType.series.index);
    animeFolders = _foldersFor(ContentType.anime.index);
  }

  List<_SearchFolder> _foldersFor(int type) {
    final items = <int>[];
    var anyFolder = false;
    for (var i = 0; i < types.length; i++) {
      if (types[i] != type) continue;
      items.add(i);
      if (folders[i]) anyFolder = true;
    }
    if (anyFolder) {
      return [
        for (final i in items)
          if (folders[i])
            _SearchFolder(ids[i], names[i], groups[i], seriesKeys[i]),
      ];
    }
    final grouped = <String, List<int>>{};
    for (final i in items) {
      final key = seriesKeys[i].isEmpty ? ids[i] : seriesKeys[i];
      (grouped[key] ??= []).add(i);
    }
    final out = <_SearchFolder>[];
    for (final entry in grouped.entries) {
      final members = entry.value
        ..sort((a, b) {
          final season = seasons[a].compareTo(seasons[b]);
          if (season != 0) return season;
          final episode = episodes[a].compareTo(episodes[b]);
          if (episode != 0) return episode;
          return names[a].compareTo(names[b]);
        });
      final first = members.first;
      final key = seriesKeys[first].isEmpty ? entry.key : seriesKeys[first];
      out.add(
        _SearchFolder(
          entry.key,
          seriesNames[first].isNotEmpty ? seriesNames[first] : names[first],
          groups[first],
          key,
        ),
      );
    }
    return out;
  }

  CatalogSearchAnswer query(CatalogSearchQuery message) {
    final q = message.query.trim().toLowerCase();
    if (q.isEmpty) return CatalogSearchAnswer.empty(message.id, message.epoch);
    final episodeHits = <String>{};
    final live = <int>[];
    final movie = <int>[];
    for (var i = 0; i < names.length; i++) {
      if (!names[i].contains(q)) continue;
      final key = seriesKeys[i];
      if (key.isNotEmpty) episodeHits.add(key);
      if (folders[i]) continue;
      final type = types[i];
      if (type == ContentType.live.index) {
        live.add(i);
      } else if (type == ContentType.movie.index) {
        movie.add(i);
      }
    }
    return CatalogSearchAnswer(
      id: message.id,
      epoch: message.epoch,
      stale: false,
      live: live,
      movie: movie,
      seriesIds: _matchingFolders(seriesFolders, q, episodeHits),
      animeIds: _matchingFolders(animeFolders, q, episodeHits),
    );
  }

  List<String> _matchingFolders(
    List<_SearchFolder> folders,
    String q,
    Set<String> episodeHits,
  ) {
    final out = <String>[];
    for (final folder in folders) {
      final byEpisode =
          folder.seriesKey.isNotEmpty && episodeHits.contains(folder.seriesKey);
      if (byEpisode ||
          folder.nameLower.contains(q) ||
          folder.groupLower.contains(q)) {
        out.add(folder.id);
      }
    }
    return out;
  }
}

/// Holds one catalog snapshot and answers queries without touching the UI.
void catalogSearchWorker(SendPort toMain) {
  final inbox = ReceivePort();
  toMain.send(inbox.sendPort);
  final memory = _SearchMemory();
  var epoch = -1;
  var ready = false;
  inbox.listen((message) {
    try {
      if (message is CatalogSearchReset) {
        if (message.epoch >= epoch) {
          epoch = message.epoch;
          ready = false;
          memory.clear();
        }
      } else if (message is CatalogSearchChunk) {
        if (message.epoch == epoch) memory.add(message);
      } else if (message is CatalogSearchCommit) {
        if (message.epoch != epoch) return;
        memory.rebuildFolders();
        ready = true;
        toMain.send(CatalogSearchReady(epoch));
      } else if (message is CatalogSearchQuery) {
        if (!ready || message.epoch != epoch) {
          toMain.send(
            CatalogSearchAnswer.empty(message.id, message.epoch, stale: true),
          );
          return;
        }
        toMain.send(memory.query(message));
      }
    } catch (_) {
      if (message is CatalogSearchQuery) {
        toMain.send(CatalogSearchAnswer.empty(message.id, message.epoch));
      } else if (message is CatalogSearchCommit) {
        toMain.send(CatalogSearchReady(message.epoch));
      }
    }
  });
}

/// Duplicate key for one catalog title: same type and same sanitized name
/// (language prefixes, quality tags, brackets and punctuation removed).
/// Live channels keep their id, since equal names can be different feeds.
String catalogEntryKey(Channel c) {
  if (c.type == ContentType.live) return c.id;
  final k = catalogTitleKey(
    CatalogBuilder.stripQuality(c.seriesName ?? c.name),
  );
  return k.isEmpty ? c.id : '${c.type.name}:$k';
}
