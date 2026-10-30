import 'dart:isolate';

import '../models/channel.dart';
import 'catalog_builder.dart';
import 'title_matching.dart';

/// "Aggiunto" uses the provider's addition date; "Uscita" uses the real
/// release date of the title (VOD catalogs only).
enum CatalogSort {
  provider('Predefinito'),
  nameAsc('A–Z'),
  nameDesc('Z–A'),
  dateAsc('Primo aggiunto'),
  dateDesc('Ultimo aggiunto'),
  releaseDesc('Uscita più recente'),
  releaseAsc('Uscita meno recente'),
  rating('Voto IMDb');

  const CatalogSort(this.label);
  final String label;

  /// Options meaningful only for films and series.
  bool get vodOnly =>
      this == rating || this == releaseDesc || this == releaseAsc;
}

List<T> sortCatalog<T>(
  Iterable<T> items,
  CatalogSort? order,
  Channel Function(T) channel, {
  double? Function(Channel)? ratingOf,
}) {
  final list = items.toList();
  if (order == null || order == CatalogSort.provider) return list;
  final names = <String, String>{};
  String name(Channel c) =>
      names.putIfAbsent(c.id, () => c.displaySeriesName.toLowerCase());
  final ratings = <String, double>{};
  double rating(Channel c) =>
      ratings.putIfAbsent(c.id, () => ratingOf?.call(c) ?? 0);
  final releases = <String, int>{};
  int release(Channel c) => releases.putIfAbsent(c.id, () => c.releaseKey);
  int byRelease(Channel a, Channel b, bool newest) {
    final ra = release(a), rb = release(b);
    if (ra == 0 || rb == 0) return ra == rb ? 0 : (ra == 0 ? 1 : -1);
    return newest ? rb.compareTo(ra) : ra.compareTo(rb);
  }

  list.sort((a, b) {
    final ca = channel(a), cb = channel(b);
    final value = switch (order) {
      CatalogSort.provider => 0,
      CatalogSort.nameAsc => name(ca).compareTo(name(cb)),
      CatalogSort.nameDesc => name(cb).compareTo(name(ca)),
      CatalogSort.dateAsc =>
        ca.addedAt == 0 || cb.addedAt == 0
            ? (ca.addedAt == 0 ? 1 : -1)
            : ca.addedAt.compareTo(cb.addedAt),
      CatalogSort.dateDesc => cb.addedAt.compareTo(ca.addedAt),
      CatalogSort.releaseDesc => byRelease(ca, cb, true),
      CatalogSort.releaseAsc => byRelease(ca, cb, false),
      CatalogSort.rating => rating(cb).compareTo(rating(ca)),
    };
    if (ca.addedAt == 0 && cb.addedAt == 0 && order == CatalogSort.dateAsc) {
      return name(ca).compareTo(name(cb));
    }
    if (value != 0) return value;
    final alpha = name(ca).compareTo(name(cb));
    return alpha != 0 ? alpha : ca.id.compareTo(cb.id);
  });
  return list;
}

// Top-level boundary: isolate closure cannot capture widget State/context.
Future<List<CatalogEntry>> sortCatalogBackground(
  List<CatalogEntry> entries,
  CatalogSort? order,
  Map<String, double> ratings,
) => Isolate.run(
  () => sortCatalog(
    entries,
    order,
    (e) => e.primary,
    ratingOf: (c) => ratings[c.id],
  ),
);

Future<List<Channel>> sortLiveBackground(
  List<Channel> channels,
  CatalogSort? order,
) => Isolate.run(() => sortCatalog(channels, order, (c) => c));

/// IMDb when the snapshot has a positive score, otherwise the stored vote.
/// A missing score stays 0 and sorts after every rated title.
Future<List<CatalogEntry>> sortCatalogByKnownRatings(
  List<CatalogEntry> entries,
  Map<String, double> tmdbByTitle,
  Map<String, String> imdbKeyByTitle,
  Map<String, double> imdbByKey,
) => Isolate.run(
  () => _sortByKnownRatings(entries, tmdbByTitle, imdbKeyByTitle, imdbByKey),
);

List<CatalogEntry> _sortByKnownRatings(
  List<CatalogEntry> entries,
  Map<String, double> tmdbByTitle,
  Map<String, String> imdbKeyByTitle,
  Map<String, double> imdbByKey,
) {
  final scores = <String, double>{};
  for (final entry in entries) {
    final channel = entry.primary;
    final titleKey = parseTitle(channel.displaySeriesName)
        .key(channel.type.name);
    final imdbKey = imdbKeyByTitle[titleKey];
    final imdb = imdbKey == null ? null : imdbByKey[imdbKey];
    final score = imdb != null && imdb > 0
        ? imdb
        : (tmdbByTitle[titleKey] ?? 0);
    if (score > 0) scores[channel.id] = score;
  }
  return sortCatalog(
    entries,
    CatalogSort.rating,
    (entry) => entry.primary,
    ratingOf: (channel) => scores[channel.id] ?? 0,
  );
}

/// Highest known score first. A missing or zero score is omitted so the
/// caller can leave those titles in their current order.
List<String> rankKnownTitleIds(
  List<String> ids,
  List<String> names,
  String typeName,
  Map<String, double> scoresByTitle,
) {
  final scores = List<double>.generate(ids.length, (i) {
    if (i >= names.length) return 0;
    return scoresByTitle[parseTitle(names[i]).key(typeName)] ?? 0;
  }, growable: false);
  final order = <int>[];
  for (var i = 0; i < scores.length; i++) {
    if (scores[i] > 0) order.add(i);
  }
  order.sort((a, b) {
    final byScore = scores[b].compareTo(scores[a]);
    if (byScore != 0) return byScore;
    final byName = names[a].toLowerCase().compareTo(names[b].toLowerCase());
    return byName != 0 ? byName : ids[a].compareTo(ids[b]);
  });
  return [for (final i in order) ids[i]];
}

/// Highest score first. Equal scores keep alphabetical order. A missing
/// score is 0 and therefore lands after every rated title.
List<int> indicesByRating(List<double> scores, List<String> names) {
  final order = List<int>.generate(scores.length, (i) => i);
  order.sort((a, b) {
    final byScore = scores[b].compareTo(scores[a]);
    if (byScore != 0) return byScore;
    final byName = names[a].compareTo(names[b]);
    return byName != 0 ? byName : a.compareTo(b);
  });
  return order;
}

/// Reorders [entries] with a previously saved id list. Unknown titles keep
/// their incoming order at the end, so a new title never disappears.
List<CatalogEntry> applyCatalogOrder(
  List<CatalogEntry> entries,
  List<String> ids,
) {
  final byId = <String, CatalogEntry>{};
  for (final entry in entries) {
    byId.putIfAbsent(entry.primary.id, () => entry);
  }
  final used = <String>{};
  final ordered = <CatalogEntry>[];
  for (final id in ids) {
    final entry = byId[id];
    if (entry != null && used.add(id)) ordered.add(entry);
  }
  if (ordered.length == entries.length) return ordered;
  for (final entry in entries) {
    if (used.add(entry.primary.id)) ordered.add(entry);
  }
  return ordered;
}
