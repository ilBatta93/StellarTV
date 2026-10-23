import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/custom_category.dart';
import 'catalog_builder.dart';
import 'catalog_index_builder.dart' show catalogTitleKey;

/// Bounded cooperative work: no full catalog copy is sent to a second heap.
/// Every batch yields to input and checks whether the owner still permits work.
class CatalogYield {
  CatalogYield(this.allowed);
  final Future<bool> Function() allowed;
  final Stopwatch _clock = Stopwatch()..start();
  int _items = 0;
  Future<void> step() async {
    // Time budget only: ~6 ms of work per frame, then one event-loop turn.
    if ((++_items & 255) != 0 || _clock.elapsedMicroseconds < 6000) return;
    await Future<void>.delayed(Duration.zero);
    if (!await allowed()) throw const CatalogPreparationCancelled();
    _clock.reset();
  }
}

class CatalogPreparationCancelled implements Exception {
  const CatalogPreparationCancelled();
}

Future<List<T>> catalogMergeSort<T>(
  List<T> input,
  int Function(T, T) compare,
  CatalogYield yieldWork,
) async {
  var source = <T>[];
  for (final item in input) {
    source.add(item);
    await yieldWork.step();
  }
  for (var width = 1; width < source.length; width *= 2) {
    final next = <T>[];
    for (var start = 0; start < source.length; start += width * 2) {
      var left = start;
      final middle = (start + width).clamp(0, source.length);
      var right = middle;
      final end = (start + width * 2).clamp(0, source.length);
      while (left < middle || right < end) {
        if (right >= end ||
            (left < middle && compare(source[left], source[right]) <= 0)) {
          next.add(source[left++]);
        } else {
          next.add(source[right++]);
        }
        await yieldWork.step();
      }
    }
    source = next;
  }
  return source;
}

class PreparedCatalog {
  const PreparedCatalog(
    this.channels,
    this.catalog,
    this.groups,
    this.recent,
    this.all,
  );
  final List<Channel> channels;
  final List<Channel> catalog;
  final List<CatalogGroup> groups;
  final List<CatalogEntry> recent;
  final List<CatalogEntry> all;
}

Future<PreparedCatalog> prepareCatalog({
  required List<Channel> snapshot,
  required ContentType type,
  required Set<String> hidden,
  required List<CustomCategory> custom,
  required List<String> order,
  required CatalogYield yieldWork,
  void Function(List<CatalogGroup>, List<CatalogEntry>)? onProgress,
}) async {
  final channels = <Channel>[];
  final categoryOrder = <String>{};
  for (final c in snapshot) {
    if (c.type == type) {
      channels.add(c);
      if ((type != ContentType.series && type != ContentType.anime) ||
          c.isSeriesFolder) {
        categoryOrder.add(c.group);
      }
    }
    await yieldWork.step();
  }
  List<Channel> catalog = channels;
  if (type == ContentType.series || type == ContentType.anime) {
    final folders = <Channel>[];
    final episodes = <String, List<Channel>>{};
    for (final c in channels) {
      if (c.isSeriesFolder) {
        folders.add(c);
      } else {
        (episodes[c.seriesKey ?? c.id] ??= []).add(c);
      }
      await yieldWork.step();
    }
    if (folders.isEmpty) {
      for (final items in episodes.values) {
        // Only one show's episodes at a time; preserves the existing folder contract.
        final sorted = await catalogMergeSort(items, (a, b) {
          final season = (a.season ?? 0).compareTo(b.season ?? 0);
          if (season != 0) return season;
          final episode = (a.episode ?? 0).compareTo(b.episode ?? 0);
          return episode != 0
              ? episode
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        }, yieldWork);
        final first = sorted.first;
        var logo = first.logo;
        for (final item in sorted) {
          if (item.logo.isNotEmpty) {
            logo = item.logo;
            break;
          }
          await yieldWork.step();
        }
        folders.add(
          first.copyWith(
            id: first.seriesKey ?? first.id,
            name: first.displaySeriesName,
            url: '',
            logo: logo,
            seriesKey: first.seriesKey ?? first.id,
            seriesName: first.displaySeriesName,
            isSeriesFolder: true,
            episodeCount: items.length,
          ),
        );
        await yieldWork.step();
      }
    }
    catalog = await catalogMergeSort(
      folders,
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      yieldWork,
    );
  }
  final byCategory = <String, List<Channel>>{};
  final other = <Channel>[];
  final visible = <Channel>[];
  for (final c in catalog) {
    if (!hidden.contains(c.group)) {
      visible.add(c);
      if (categoryOrder.contains(c.group)) {
        (byCategory[c.group] ??= []).add(c);
      } else {
        other.add(c);
      }
    }
    await yieldWork.step();
  }
  final base = <CatalogGroup>[];
  final seen = <String>{};
  final byId = <String, CatalogEntry>{};
  for (final label in [
    ...categoryOrder.where((g) => !hidden.contains(g)),
    if (other.isNotEmpty) 'Altri',
  ]) {
    final entries = <CatalogEntry>[];
    final local = <String>{};
    final items = label == 'Altri' && !byCategory.containsKey(label)
        ? other
        : byCategory[label] ?? const <Channel>[];
    for (final c in items) {
      final key = type == ContentType.live
          ? c.id
          : '${c.type.name}:${CatalogBuilder.normalize(CatalogBuilder.stripQuality(c.seriesName ?? c.name))}';
      if (local.add(c.id) && seen.add(key)) {
        final entry = CatalogEntry(primary: c, variants: [c]);
        entries.add(entry);
        byId[c.id] = entry;
      }
      await yieldWork.step();
    }
    if (entries.isNotEmpty)
      base.add(CatalogGroup(label: label, entries: entries));
  }
  final labels = <String, CatalogGroup>{};
  for (final c in custom) {
    final entries = <CatalogEntry>[];
    for (final id in c.itemIds) {
      final entry = byId[id];
      if (entry != null) entries.add(entry);
      await yieldWork.step();
    }
    labels[c.name] = CatalogGroup(label: c.name, entries: entries);
  }
  for (final group in base) {
    labels.putIfAbsent(group.label, () => group);
    await yieldWork.step();
  }
  final groups = <CatalogGroup>[];
  for (final label in applyCategoryOrder(labels.keys.toList(), order)) {
    final group = labels[label];
    if (group != null && group.entries.isNotEmpty) groups.add(group);
  }
  final indexed = <(int, Channel)>[];
  for (var i = 0; i < visible.length; i++) {
    indexed.add((i, visible[i]));
    await yieldWork.step();
  }
  final newest = await catalogMergeSort(indexed, (a, b) {
    final date = b.$2.addedAt.compareTo(a.$2.addedAt);
    return date != 0 ? date : b.$1.compareTo(a.$1);
  }, yieldWork);
  String key(Channel c) {
    final name = catalogTitleKey(c.seriesName ?? c.name);
    return name.isEmpty ? c.id : '${c.type.name}:$name';
  }

  final recent = <CatalogEntry>[];
  final recentSeen = <String>{};
  for (final (_, c) in newest) {
    if (recentSeen.add(key(c)))
      recent.add(CatalogEntry(primary: c, variants: [c]));
    if (recent.length == 100) break;
    await yieldWork.step();
  }
  onProgress?.call(groups, recent);
  final all = <CatalogEntry>[];
  final allSeen = <String>{};
  for (final group in groups) {
    for (final entry in group.entries) {
      if (allSeen.add(key(entry.primary))) all.add(entry);
      await yieldWork.step();
    }
  }
  final alphabetical = await catalogMergeSort(
    all,
    (a, b) =>
        a.primary.name.toLowerCase().compareTo(b.primary.name.toLowerCase()),
    yieldWork,
  );
  return PreparedCatalog(channels, catalog, groups, recent, alphabetical);
}
