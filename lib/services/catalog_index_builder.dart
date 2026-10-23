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
  final series =
      alreadyGrouped.$1 ? seriesItems : SeriesGrouping.catalog(seriesItems);
  final anime =
      alreadyGrouped.$2 ? animeItems : SeriesGrouping.catalog(animeItems);
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
String catalogTitleKey(String raw) => TmdbService.cleanTitle(raw)
    .toLowerCase()
    .replaceAll(_langPrefix, '')
    .replaceAll(_brackets, ' ')
    .replaceAll(_nonWord, ' ')
    .trim();

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
