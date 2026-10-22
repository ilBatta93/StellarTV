import 'dart:isolate';
import '../models/channel.dart';
import 'catalog_builder.dart';

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
  rating('Voto');

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
