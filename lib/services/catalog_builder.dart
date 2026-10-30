import 'catalog_index_builder.dart' show catalogEntryKey;
import '../models/channel.dart';

/// One deduplicated catalog entry: a title plus all the alternative copies
/// (different qualities, e.g. 1080p and 4K) found across categories.
class CatalogEntry {
  final Channel? _bound;
  final int? _slot;
  final CatalogChannelSource? _source;
  final List<Channel>? _boundVariants;
  final List<int>? _variantSlots;

  const CatalogEntry({
    required Channel primary,
    required List<Channel> variants,
  }) : _bound = primary,
       _slot = null,
       _source = null,
       _boundVariants = variants,
       _variantSlots = null;

  /// Resolves the title from the indexed shelf the first time a tile reads it.
  CatalogEntry.slot(
    int slot,
    CatalogChannelSource source, {
    List<int>? variants,
  }) : _bound = null,
       _slot = slot,
       _source = source,
       _boundVariants = null,
       _variantSlots = variants;

  Channel get primary => _bound ?? _source!.readSlot(_slot!);

  List<Channel> get variants =>
      _boundVariants ??
      [
        for (final slot in _variantSlots ?? <int>[_slot!])
          _source!.readSlot(slot),
      ];

  int? get shelfSlot => _slot;
}

/// Windowed read used by [CatalogEntry.slot]. Implemented by the shelf.
abstract class CatalogChannelSource {
  Channel readSlot(int slot);
}

/// Groups and deduplicates channels for the catalog pages.
///
/// - Category order follows the playlist's own category list (given by the
///   caller), never alphabetical re-sorting.
/// - The same title appearing in several categories is shown once, under the
///   first category that contains it.
/// - Copies that only differ by quality (4K / 1080p, SD, HEVC, ...) are kept
///   as variants of the same entry so the viewer can pick one when opening.
class CatalogBuilder {
  static final _qualityTag = RegExp(
    r'[\[\(]\s*(4k|2160p?|1080[pi]?|720p?|480p?|sd|hd|h[qQ]|fhd|uhd|hevc|h265|x265)\s*[\]\)]|'
    r'\b(4k|2160p?|1080[pi]?|720p?|480p?|fhd|uhd)\b',
    caseSensitive: false,
  );

  /// Removes a quality tag from a name so "Film [4K]" and "Film (1080p)"
  /// normalize to the same base title.
  static String stripQuality(String name) {
    var out = name.replaceAll(_qualityTag, ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out;
  }

  static String? qualityLabel(String name) {
    final match = _qualityTag.firstMatch(name);
    if (match == null) return null;
    final tag = (match.group(1) ?? match.group(2) ?? '').toUpperCase();
    return switch (tag) {
      '2160P' || '4K' || 'UHD' => '4K',
      '1080P' || 'FHD' => '1080p',
      '720P' || 'HD' => '720p',
      '480P' || 'SD' => 'SD',
      'HEVC' || 'H265' || 'X265' => 'HEVC',
      _ => tag,
    };
  }

  /// Groups playable items of one type into entries, keeping the first
  /// appearance order of `channels` (already in playlist category order).
  /// Series folders are passed through untouched.
  static List<CatalogEntry> entriesOf(List<Channel> channels) {
    // Basic handling: one entry per playlist item, only exact duplicates
    // (same id) are skipped.
    final seen = <String>{};
    return [
      for (final c in channels)
        if (seen.add(c.id)) CatalogEntry(primary: c, variants: [c]),
    ];
  }

  /// Groups by category, preserving the playlist's category order. Titles
  /// repeated in later categories are omitted there (dedup across groups).
  static List<CatalogGroup> groupsOf(
    List<Channel> channels,
    List<String> categoryOrder,
  ) {
    final seenGlobal = <String>{};
    final groups = <CatalogGroup>[];

    void addGroup(String label, List<Channel> items) {
      final entries = <CatalogEntry>[];
      for (final entry in entriesOf(items)) {
        final c = entry.primary;
        final key = catalogEntryKey(c);
        if (!seenGlobal.add(key)) continue;
        entries.add(entry);
      }
      if (entries.isNotEmpty) {
        groups.add(CatalogGroup(label: label, entries: entries));
      }
    }

    final byCategory = <String, List<Channel>>{};
    final uncategorized = <Channel>[];
    final known = categoryOrder.toSet();
    for (final c in channels) {
      if (known.contains(c.group)) {
        byCategory.putIfAbsent(c.group, () => []).add(c);
      } else {
        uncategorized.add(c);
      }
    }
    for (final label in categoryOrder) {
      final items = byCategory[label];
      if (items != null && items.isNotEmpty) addGroup(label, items);
    }
    if (uncategorized.isNotEmpty) addGroup('Altri', uncategorized);
    return groups;
  }

  static String normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9à-ÿ]+'), ' ').trim();
}

/// One category section of the catalog, in playlist order.
class CatalogGroup {
  final String label;
  final List<CatalogEntry> entries;

  const CatalogGroup({required this.label, required this.entries});
}
