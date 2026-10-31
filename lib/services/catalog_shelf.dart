import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/custom_category.dart';
import 'catalog_builder.dart';
import 'catalog_index_builder.dart' show catalogEntryKey, catalogTitleKey;
import 'catalog_preparation.dart';
import 'catalog_sort.dart';
import 'kids_content_service.dart';
import 'kids_policy.dart';

/// Adult titles are flagged while the shelf is built, so the provider can
/// hide them without keeping the raw catalog.
const shelfFlagAdult = 1;
const shelfFlagFolder = 2;
const shelfFlagBanned = 4;
const shelfFlagSynthetic = 8;
const shelfFlagKids = 16;

final _adultPattern = RegExp(
  r'\bx{3,}\b|for\s*adults?|\badults?\b|\badulti\b|\b18\s*\+|\+\s*18\b|'
  r'\bp0rn|\bhentai\b|\beroti[ck]|\bsexy?\b|\bhot\s*club\b|'
  r'playboy|brazzers|dorcel|hustler|penthouse|redlight|red\s*light|'
  r'private\s*(tv|spice)|\bspice\b|vivid|xxl\s*tv|blue\s*hustler|\bnsfw\b|milf',
  caseSensitive: false,
);
final _adultExceptions = RegExp(
  r'adult\s*swim|young\s*adults?',
  caseSensitive: false,
);
final _wordSplit = RegExp(r'[^a-z0-9à-ÿ]+');

bool catalogTextIsAdult(String? value) {
  if (value == null || value.isEmpty) return false;
  return _adultPattern.hasMatch(value.replaceAll(_adultExceptions, ' '));
}

bool catalogChannelIsAdult(Channel channel) =>
    catalogTextIsAdult(channel.group) ||
    catalogTextIsAdult(channel.name) ||
    catalogTextIsAdult(channel.seriesName);

String shelfFacetKey(Channel channel) {
  final type = channel.type == ContentType.movie ? 'movie' : 'tv';
  final title = channel.seriesName?.trim().isNotEmpty == true
      ? channel.seriesName!
      : channel.name;
  final norm = title.toLowerCase().replaceAll(_wordSplit, ' ').trim();
  return '$type:$norm';
}

String shelfSettingsToken({
  required Map<String, List<String>> hidden,
  required List<CustomCategory> custom,
  required Map<String, List<String>> order,
}) {
  final buffer = StringBuffer();
  final hiddenKeys = hidden.keys.toList()..sort();
  for (final key in hiddenKeys) {
    final values = [...?hidden[key]]..sort();
    buffer.write('$key=${values.join(',')};');
  }
  buffer.write('|');
  for (final category in custom) {
    buffer.write(
      '${category.type.name}:${category.name}:${category.itemIds.join(',')};',
    );
  }
  buffer.write('|');
  final orderKeys = order.keys.toList()..sort();
  for (final key in orderKeys) {
    buffer.write('$key=${order[key]?.join(',')};');
  }
  return buffer.toString();
}

/// One prepared section as slot indexes into the shelf, not as titles.
class ShelfPlan {
  const ShelfPlan({
    required this.channels,
    required this.catalog,
    required this.labels,
    required this.groupSlots,
    required this.recent,
    required this.alphabetical,
  });

  final List<int> channels;
  final List<int> catalog;
  final List<String> labels;
  final List<List<int>> groupSlots;
  final List<int> recent;
  final List<int> alphabetical;

  static ShelfPlan fromPrepared(
    PreparedCatalog prepared,
    Map<Channel, int> slotOf,
  ) {
    int slot(Channel channel) {
      final index = slotOf[channel];
      if (index == null) {
        throw StateError('Titolo preparato assente dallo scaffale');
      }
      return index;
    }

    List<int> entries(List<CatalogEntry> list) => [
      for (final entry in list) slot(entry.primary),
    ];

    return ShelfPlan(
      channels: [for (final channel in prepared.channels) slot(channel)],
      catalog: [for (final channel in prepared.catalog) slot(channel)],
      labels: [for (final group in prepared.groups) group.label],
      groupSlots: [for (final group in prepared.groups) entries(group.entries)],
      recent: entries(prepared.recent),
      alphabetical: entries(prepared.all),
    );
  }
}

class _ShelfImage {
  const _ShelfImage({
    required this.paths,
    required this.ids,
    required this.types,
    required this.fileOf,
    required this.offsets,
    required this.lengths,
    required this.flags,
    required this.groupOf,
    required this.groupLabels,
    required this.facetKeys,
    required this.words,
    required this.wordStarts,
    required this.wordPostings,
    required this.exactKeys,
    required this.exactStarts,
    required this.exactPostings,
    required this.episodes,
    required this.folders,
    required this.titleCategories,
    required this.categoryLabels,
    required this.plans,
    required this.settingsToken,
  });

  final List<String> paths;
  final List<String> ids;
  final List<int> types;
  final List<int> fileOf;
  final List<int> offsets;
  final List<int> lengths;
  final List<int> flags;
  final List<int> groupOf;
  final List<String> groupLabels;
  final List<String> facetKeys;
  final List<String> words;
  final List<int> wordStarts;
  final List<int> wordPostings;
  final List<String> exactKeys;
  final List<int> exactStarts;
  final List<int> exactPostings;
  final Map<String, List<int>> episodes;
  final Map<String, int> folders;
  final Map<String, List<String>> titleCategories;
  final Map<String, List<String>> categoryLabels;
  final Map<String, ShelfPlan> plans;
  final String settingsToken;
}

class _WrittenLine {
  const _WrittenLine(this.offset, this.length);
  final int offset;
  final int length;
}

_WrittenLine _appendChannel(
  RandomAccessFile file,
  int offset,
  Channel channel, {
  bool synthetic = false,
}) {
  final map = channel.toMap();
  if (synthetic) map['shelf_synthetic'] = true;
  final line = utf8.encode('${jsonEncode(map)}\n');
  file.writeFromSync(line);
  return _WrittenLine(offset, line.length - 1);
}

class _LineIndex {
  _LineIndex({
    required this.ids,
    required this.types,
    required this.fileOf,
    required this.offsets,
    required this.lengths,
    required this.flags,
    required this.groupOf,
    required this.groupLabels,
    required this.facetKeys,
  });

  final List<String> ids;
  final List<int> types;
  final List<int> fileOf;
  final List<int> offsets;
  final List<int> lengths;
  final List<int> flags;
  final List<int> groupOf;
  final List<String> groupLabels;
  final List<String> facetKeys;
}

_LineIndex _indexChannels(
  List<Channel> channels,
  List<int> fileOf,
  List<int> offsets,
  List<int> lengths, {
  List<bool> synthetic = const [],
}) {
  final groupLabels = <String>[''];
  final groupSlot = <String, int>{'': 0};
  final ids = <String>[];
  final types = <int>[];
  final flags = <int>[];
  final groupOf = <int>[];
  final facetKeys = <String>[];
  for (final channel in channels) {
    ids.add(channel.id);
    types.add(channel.type.index);
    var flag = 0;
    if (catalogChannelIsAdult(channel)) flag |= shelfFlagAdult;
    if (channel.isSeriesFolder) flag |= shelfFlagFolder;
    if (synthetic.length > flags.length && synthetic[flags.length]) {
      flag |= shelfFlagSynthetic;
    }
    if (KidsContentService.bannedKeywords.hasMatch(
      '${channel.name} ${channel.group} ${channel.seriesName ?? ''} ${channel.plot ?? ''}',
    )) {
      flag |= shelfFlagBanned;
    }
    if ((flag & (shelfFlagAdult | shelfFlagBanned)) == 0 &&
        KidsPolicy.allows(category: channel.group)) {
      flag |= shelfFlagKids;
    }
    flags.add(flag);
    final group = channel.group;
    groupOf.add(
      groupSlot.putIfAbsent(group, () {
        groupLabels.add(group);
        return groupLabels.length - 1;
      }),
    );
    facetKeys.add(shelfFacetKey(channel));
  }
  return _LineIndex(
    ids: ids,
    types: types,
    fileOf: fileOf,
    offsets: offsets,
    lengths: lengths,
    flags: flags,
    groupOf: groupOf,
    groupLabels: groupLabels,
    facetKeys: facetKeys,
  );
}

void _addWords(Map<String, List<int>> buckets, String text, int slot) {
  if (text.isEmpty) return;
  final seen = <String>{};
  for (final word in text.toLowerCase().split(_wordSplit)) {
    if (word.length < 2 || !seen.add(word)) continue;
    (buckets[word] ??= <int>[]).add(slot);
  }
}

({List<String> keys, List<int> starts, List<int> postings}) _flatten(
  Map<String, List<int>> buckets,
) {
  final keys = buckets.keys.toList()..sort();
  final starts = <int>[0];
  final postings = <int>[];
  for (final key in keys) {
    postings.addAll(buckets[key]!);
    starts.add(postings.length);
  }
  return (keys: keys, starts: starts, postings: postings);
}

int _lowerBound(List<String> keys, String token) {
  var low = 0;
  var high = keys.length;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (keys[mid].compareTo(token) < 0) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}

_ShelfImage _finishImage({
  required List<String> paths,
  required List<Channel> channels,
  required List<int> fileOf,
  required List<int> offsets,
  required List<int> lengths,
  required Map<String, ShelfPlan> plans,
  required String settingsToken,
  List<bool> synthetic = const [],
}) {
  final indexed = _indexChannels(
    channels,
    fileOf,
    offsets,
    lengths,
    synthetic: synthetic,
  );
  final words = <String, List<int>>{};
  final exact = <String, List<int>>{};
  final episodes = <String, List<int>>{};
  final folders = <String, int>{};
  final titleCategories = <String, Set<String>>{};
  final categorySeen = <String, Set<String>>{};
  final categoryLabels = <String, List<String>>{};
  final folderBySeries = <ContentType, bool>{};

  for (final channel in channels) {
    if (channel.isSeriesFolder) folderBySeries[channel.type] = true;
  }
  for (var slot = 0; slot < channels.length; slot++) {
    final channel = channels[slot];
    final seriesLike =
        channel.type == ContentType.series || channel.type == ContentType.anime;
    if (!seriesLike ||
        !(folderBySeries[channel.type] ?? false) ||
        channel.isSeriesFolder) {
      final labels = categoryLabels[channel.type.name] ??= <String>[];
      final seen = categorySeen[channel.type.name] ??= <String>{};
      if (channel.group.isNotEmpty && seen.add(channel.group)) {
        labels.add(channel.group);
      }
    }
    if (seriesLike && !channel.isSeriesFolder) {
      final key = channel.seriesKey?.isNotEmpty == true
          ? channel.seriesKey!
          : channel.id;
      (episodes[key] ??= <int>[]).add(slot);
    }
    if (channel.isSeriesFolder || channel.type == ContentType.live) {
      folders[channel.id] = slot;
      final seriesKey = channel.seriesKey;
      if (seriesKey != null && seriesKey.isNotEmpty) folders[seriesKey] = slot;
    }
    final entryKey = catalogEntryKey(channel);
    if (channel.group.isNotEmpty) {
      (titleCategories[entryKey] ??= <String>{}).add(channel.group);
    }
    final title = catalogTitleKey(channel.seriesName ?? channel.name);
    if (title.isNotEmpty) (exact[title] ??= <int>[]).add(slot);
  }

  for (var slot = 0; slot < channels.length; slot++) {
    final channel = channels[slot];
    final target = channel.isSeriesFolder
        ? slot
        : folders[channel.seriesKey ?? ''] ?? folders[channel.id] ?? slot;
    _addWords(words, channel.name, target);
    final seriesName = channel.seriesName;
    if (seriesName != null && seriesName.isNotEmpty) {
      _addWords(words, seriesName, target);
    }
    if (channel.isSeriesFolder || channel.type == ContentType.live) {
      _addWords(words, channel.group, target);
    }
    if (channel.type == ContentType.live) {
      final tvgName = channel.tvgName;
      if (tvgName != null && tvgName.isNotEmpty) {
        _addWords(words, tvgName, target);
      }
      final tvgId = channel.tvgId;
      if (tvgId != null && tvgId.isNotEmpty) _addWords(words, tvgId, target);
    }
  }

  final flatWords = _flatten(words);
  final flatExact = _flatten(exact);
  return _ShelfImage(
    paths: paths,
    ids: indexed.ids,
    types: indexed.types,
    fileOf: indexed.fileOf,
    offsets: indexed.offsets,
    lengths: indexed.lengths,
    flags: indexed.flags,
    groupOf: indexed.groupOf,
    groupLabels: indexed.groupLabels,
    facetKeys: indexed.facetKeys,
    words: flatWords.keys,
    wordStarts: flatWords.starts,
    wordPostings: flatWords.postings,
    exactKeys: flatExact.keys,
    exactStarts: flatExact.starts,
    exactPostings: flatExact.postings,
    episodes: episodes,
    folders: folders,
    titleCategories: {
      for (final entry in titleCategories.entries)
        entry.key: entry.value.toList(growable: false),
    },
    categoryLabels: categoryLabels,
    plans: plans,
    settingsToken: settingsToken,
  );
}

Map<String, ShelfPlan> _plansFor(
  List<Channel> channels,
  Map<String, List<String>> hidden,
  List<CustomCategory> custom,
  Map<String, List<String>> order,
  Map<Channel, int> slotOf,
) {
  final plans = <String, ShelfPlan>{};
  for (final type in ContentType.values) {
    final prepared = prepareCatalogSync(
      snapshot: channels,
      type: type,
      hidden: hidden[type.name] ?? const [],
      custom: [
        for (final category in custom)
          if (category.type == type) category,
      ],
      order: order[type.name] ?? const [],
    );
    for (final channel in [
      ...prepared.channels,
      ...prepared.catalog,
      for (final group in prepared.groups)
        for (final entry in group.entries) entry.primary,
    ]) {
      if (!slotOf.containsKey(channel)) {
        slotOf[channel] = slotOf.length;
        channels.add(channel);
      }
    }
    plans[type.name] = ShelfPlan.fromPrepared(prepared, slotOf);
  }
  return plans;
}

/// Builds the shelf from titles already in memory. The list stays in this
/// isolate; the caller receives indexes and file offsets only.
_ShelfImage _buildShelfFromChannels(
  String directory,
  List<Channel> snapshot,
  Map<String, List<String>> hidden,
  List<CustomCategory> custom,
  Map<String, List<String>> order,
) {
  final channels = List<Channel>.of(snapshot);
  final slotOf = <Channel, int>{
    for (var i = 0; i < channels.length; i++) channels[i]: i,
  };
  final sourceCount = channels.length;
  final token = shelfSettingsToken(
    hidden: hidden,
    custom: custom,
    order: order,
  );
  final plans = _plansFor(channels, hidden, custom, order, slotOf);
  final synthetic = <bool>[
    for (var i = 0; i < channels.length; i++) i >= sourceCount,
  ];
  final path = '$directory/body.ndjson';
  final file = File(path).openSync(mode: FileMode.write);
  final offsets = <int>[];
  final lengths = <int>[];
  final fileOf = <int>[];
  var cursor = 0;
  try {
    for (var i = 0; i < channels.length; i++) {
      final written = _appendChannel(
        file,
        cursor,
        channels[i],
        synthetic: synthetic[i],
      );
      offsets.add(written.offset);
      lengths.add(written.length);
      fileOf.add(0);
      cursor = written.offset + written.length + 1;
    }
  } finally {
    file.closeSync();
  }
  return _finishImage(
    paths: [path],
    channels: channels,
    fileOf: fileOf,
    offsets: offsets,
    lengths: lengths,
    plans: plans,
    settingsToken: token,
    synthetic: synthetic,
  );
}

List<Channel>? _readV3(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final channels = <Channel>[];
  final lines = file.readAsBytesSync();
  var start = 0;
  var header = false;
  int? end;
  for (var i = 0; i <= lines.length; i++) {
    if (i != lines.length && lines[i] != 0x0A) continue;
    if (i == start) {
      start = i + 1;
      continue;
    }
    final text = utf8.decode(lines.sublist(start, i));
    start = i + 1;
    if (text.isEmpty) continue;
    final value = jsonDecode(text);
    if (!header) {
      if (value is! Map || value['stellar_catalog'] != 3) return null;
      header = true;
      continue;
    }
    if (value is Map && value.length == 1 && value['end'] is int) {
      end = value['end'] as int;
      continue;
    }
    if (value is Map) {
      channels.add(Channel.fromMap(value.cast<String, dynamic>()));
    }
  }
  if (end == null || end != channels.length) return null;
  return channels;
}

_ShelfImage _buildShelfFromPlainBody(
  String bodyPath,
  String directory,
  Map<String, List<String>> hidden,
  List<CustomCategory> custom,
  Map<String, List<String>> order,
) {
  final bytes = File(bodyPath).readAsBytesSync();
  final channels = <Channel>[];
  var start = 0;
  for (var i = 0; i <= bytes.length; i++) {
    if (i != bytes.length && bytes[i] != 0x0A) continue;
    if (i > start) {
      final value = jsonDecode(utf8.decode(bytes.sublist(start, i)));
      if (value is Map) {
        if (value['shelf_synthetic'] == true) {
          start = i + 1;
          continue;
        }
        channels.add(Channel.fromMap(value.cast<String, dynamic>()));
      }
    }
    start = i + 1;
  }
  return _buildShelfFromChannels(directory, channels, hidden, custom, order);
}

List<String> readShelfDisplayNames(
  String path,
  List<int> offsets,
  List<int> lengths,
  List<int> slots,
) {
  final handle = File(path).openSync();
  try {
    final names = <String>[];
    for (final slot in slots) {
      handle.setPositionSync(offsets[slot]);
      final value = jsonDecode(utf8.decode(handle.readSync(lengths[slot])));
      if (value is! Map) {
        names.add('');
        continue;
      }
      final series = value['series_name'];
      final name = value['name'];
      names.add(
        series is String && series.trim().isNotEmpty
            ? series
            : name is String
            ? name
            : '',
      );
    }
    return names;
  } finally {
    handle.closeSync();
  }
}

/// [slots] in [order], reading each title inside the isolate. The shelf
/// itself keeps open files, which cannot be sent to another isolate.
List<int> readShelfSortedSlots(
  List<String> paths,
  List<int> fileOf,
  List<int> offsets,
  List<int> lengths,
  List<int> slots,
  CatalogSort order,
) {
  final files = <int, RandomAccessFile>{};
  try {
    final rows = <(int, Channel)>[];
    for (final slot in slots) {
      final fileIndex = slot < fileOf.length ? fileOf[slot] : -1;
      if (fileIndex < 0 || fileIndex >= paths.length) continue;
      final handle = files[fileIndex] ??= File(paths[fileIndex]).openSync();
      handle.setPositionSync(offsets[slot]);
      final decoded = jsonDecode(utf8.decode(handle.readSync(lengths[slot])));
      if (decoded is! Map) continue;
      rows.add((slot, Channel.fromMap(decoded.cast<String, dynamic>())));
    }
    final sorted = [
      for (final row in sortCatalog(rows, order, (r) => r.$2)) row.$1,
    ];
    // A row that could not be read keeps its place at the end.
    if (sorted.length == slots.length) return sorted;
    final seen = sorted.toSet();
    return [
      ...sorted,
      for (final slot in slots)
        if (!seen.contains(slot)) slot,
    ];
  } finally {
    for (final file in files.values) {
      try {
        file.closeSync();
      } catch (_) {}
    }
  }
}

// Top-level so the isolate closure captures only its arguments.
Future<List<int>> _sortSlotsInIsolate(
  List<String> paths,
  List<int> fileOf,
  List<int> offsets,
  List<int> lengths,
  List<int> slots,
  CatalogSort order,
) => Isolate.run(
  () => readShelfSortedSlots(paths, fileOf, offsets, lengths, slots, order),
);

/// Nonzero [flags] of each slot's raw title name, keyed by slot.
Map<int, int> readShelfNameFlags(
  String path,
  List<int> offsets,
  List<int> lengths,
  List<int> slots,
  int Function(String name) flags,
) {
  final handle = File(path).openSync();
  try {
    final out = <int, int>{};
    for (final slot in slots) {
      handle.setPositionSync(offsets[slot]);
      final value = jsonDecode(utf8.decode(handle.readSync(lengths[slot])));
      final name = value is Map ? value['name'] : null;
      if (name is! String || name.isEmpty) continue;
      final found = flags(name);
      if (found != 0) out[slot] = found;
    }
    return out;
  } finally {
    handle.closeSync();
  }
}

_ShelfImage _buildShelfFromFiles(
  List<String> sectionPaths,
  String directory,
  Map<String, List<String>> hidden,
  List<CustomCategory> custom,
  Map<String, List<String>> order,
) {
  final channels = <Channel>[];
  for (final path in sectionPaths) {
    final rows = _readV3(path);
    if (rows == null) continue;
    channels.addAll(rows);
  }
  return _buildShelfFromChannels(directory, channels, hidden, custom, order);
}

/// One saved section. Offsets point at that file; only synthetic folders are
/// written beside it. Other sections are not opened.
_ShelfImage? _sectionImage(
  String path,
  String directory,
  Map<String, List<String>> hidden,
  List<CustomCategory> custom,
  Map<String, List<String>> order,
) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final bytes = file.readAsBytesSync();
  final channels = <Channel>[];
  final offsets = <int>[];
  final lengths = <int>[];
  var start = 0;
  var header = false;
  int? end;
  for (var i = 0; i <= bytes.length; i++) {
    if (i != bytes.length && bytes[i] != 0x0A) continue;
    if (i == start) {
      start = i + 1;
      continue;
    }
    final lineStart = start;
    final lineEnd = i;
    start = i + 1;
    if (lineEnd == lineStart) continue;
    final text = utf8.decode(bytes.sublist(lineStart, lineEnd));
    if (text.isEmpty) continue;
    final value = jsonDecode(text);
    if (!header) {
      if (value is! Map || value['stellar_catalog'] != 3) return null;
      header = true;
      continue;
    }
    if (value is Map && value.length == 1 && value['end'] is int) {
      end = value['end'] as int;
      continue;
    }
    if (value is Map) {
      channels.add(Channel.fromMap(value.cast<String, dynamic>()));
      offsets.add(lineStart);
      lengths.add(lineEnd - lineStart);
    }
  }
  if (!header || end == null || end != channels.length) return null;
  final slotOf = <Channel, int>{
    for (var i = 0; i < channels.length; i++) channels[i]: i,
  };
  final sourceCount = channels.length;
  final present = <ContentType>{for (final channel in channels) channel.type};
  final plans = <String, ShelfPlan>{};
  for (final type in ContentType.values) {
    if (!present.contains(type)) continue;
    final prepared = prepareCatalogSync(
      snapshot: channels,
      type: type,
      hidden: hidden[type.name] ?? const [],
      custom: [
        for (final category in custom)
          if (category.type == type) category,
      ],
      order: order[type.name] ?? const [],
    );
    for (final channel in [
      ...prepared.channels,
      ...prepared.catalog,
      for (final group in prepared.groups)
        for (final entry in group.entries) entry.primary,
    ]) {
      if (!slotOf.containsKey(channel)) {
        slotOf[channel] = slotOf.length;
        channels.add(channel);
      }
    }
    plans[type.name] = ShelfPlan.fromPrepared(prepared, slotOf);
  }
  final synthetic = <bool>[
    for (var i = 0; i < channels.length; i++) i >= sourceCount,
  ];
  final fileOf = <int>[];
  final allOffsets = <int>[];
  final allLengths = <int>[];
  final paths = <String>[path];
  for (var i = 0; i < sourceCount; i++) {
    fileOf.add(0);
    allOffsets.add(offsets[i]);
    allLengths.add(lengths[i]);
  }
  if (channels.length > sourceCount) {
    final syntheticPath = '$directory/synthetic_${path.hashCode}.ndjson';
    final out = File(syntheticPath).openSync(mode: FileMode.write);
    var cursor = 0;
    try {
      for (var i = sourceCount; i < channels.length; i++) {
        final written = _appendChannel(
          out,
          cursor,
          channels[i],
          synthetic: true,
        );
        fileOf.add(1);
        allOffsets.add(written.offset);
        allLengths.add(written.length);
        cursor = written.offset + written.length + 1;
      }
    } finally {
      out.closeSync();
    }
    paths.add(syntheticPath);
  }
  return _finishImage(
    paths: paths,
    channels: channels,
    fileOf: fileOf,
    offsets: allOffsets,
    lengths: allLengths,
    plans: plans,
    settingsToken: shelfSettingsToken(
      hidden: hidden,
      custom: custom,
      order: order,
    ),
    synthetic: synthetic,
  );
}

ShelfPlan _shiftPlan(ShelfPlan plan, int base) {
  if (base == 0) return plan;
  List<int> move(List<int> slots) => [for (final slot in slots) slot + base];
  return ShelfPlan(
    channels: move(plan.channels),
    catalog: move(plan.catalog),
    labels: plan.labels,
    groupSlots: [for (final group in plan.groupSlots) move(group)],
    recent: move(plan.recent),
    alphabetical: move(plan.alphabetical),
  );
}

void _absorbPostings(
  Map<String, List<int>> buckets,
  List<String> keys,
  List<int> starts,
  List<int> postings,
  int base,
) {
  for (var i = 0; i < keys.length; i++) {
    final list = buckets[keys[i]] ??= <int>[];
    for (var posting = starts[i]; posting < starts[i + 1]; posting++) {
      list.add(postings[posting] + base);
    }
  }
}

_ShelfImage _mergePieces(List<_ShelfImage> pieces, String token) {
  if (pieces.isEmpty) {
    return _ShelfImage(
      paths: const [],
      ids: const [],
      types: const [],
      fileOf: const [],
      offsets: const [],
      lengths: const [],
      flags: const [],
      groupOf: const [],
      groupLabels: const [''],
      facetKeys: const [],
      words: const [],
      wordStarts: const [0],
      wordPostings: const [],
      exactKeys: const [],
      exactStarts: const [0],
      exactPostings: const [],
      episodes: const {},
      folders: const {},
      titleCategories: const {},
      categoryLabels: const {},
      plans: const {},
      settingsToken: token,
    );
  }
  if (pieces.length == 1) return pieces.first;
  final paths = <String>[];
  final pathIndex = <String, int>{};
  int adopt(String path) => pathIndex.putIfAbsent(path, () {
    paths.add(path);
    return paths.length - 1;
  });
  final ids = <String>[];
  final types = <int>[];
  final fileOf = <int>[];
  final offsets = <int>[];
  final lengths = <int>[];
  final flags = <int>[];
  final groupOf = <int>[];
  final groupLabels = <String>[''];
  final groupSlot = <String, int>{'': 0};
  final facetKeys = <String>[];
  final words = <String, List<int>>{};
  final exact = <String, List<int>>{};
  final episodes = <String, List<int>>{};
  final folders = <String, int>{};
  final titleCategories = <String, List<String>>{};
  final categoryLabels = <String, List<String>>{};
  final plans = <String, ShelfPlan>{};
  var base = 0;
  for (final piece in pieces) {
    for (final entry in piece.plans.entries) {
      plans[entry.key] = _shiftPlan(entry.value, base);
    }
    final localGroups = <int>[];
    for (final label in piece.groupLabels) {
      localGroups.add(
        groupSlot.putIfAbsent(label, () {
          groupLabels.add(label);
          return groupLabels.length - 1;
        }),
      );
    }
    ids.addAll(piece.ids);
    types.addAll(piece.types);
    offsets.addAll(piece.offsets);
    lengths.addAll(piece.lengths);
    flags.addAll(piece.flags);
    facetKeys.addAll(piece.facetKeys);
    for (var slot = 0; slot < piece.ids.length; slot++) {
      final localFile = piece.fileOf[slot];
      final path = localFile >= 0 && localFile < piece.paths.length
          ? piece.paths[localFile]
          : piece.paths.first;
      fileOf.add(adopt(path));
      final localGroup = piece.groupOf[slot];
      groupOf.add(
        localGroup >= 0 && localGroup < localGroups.length
            ? localGroups[localGroup]
            : 0,
      );
    }
    _absorbPostings(
      words,
      piece.words,
      piece.wordStarts,
      piece.wordPostings,
      base,
    );
    _absorbPostings(
      exact,
      piece.exactKeys,
      piece.exactStarts,
      piece.exactPostings,
      base,
    );
    for (final entry in piece.episodes.entries) {
      final list = episodes[entry.key] ??= <int>[];
      for (final slot in entry.value) {
        list.add(slot + base);
      }
    }
    for (final entry in piece.folders.entries) {
      folders.putIfAbsent(entry.key, () => entry.value + base);
    }
    for (final entry in piece.titleCategories.entries) {
      final list = titleCategories[entry.key] ??= <String>[];
      for (final label in entry.value) {
        if (!list.contains(label)) list.add(label);
      }
    }
    for (final entry in piece.categoryLabels.entries) {
      final list = categoryLabels[entry.key] ??= <String>[];
      for (final label in entry.value) {
        if (!list.contains(label)) list.add(label);
      }
    }
    base += piece.ids.length;
  }
  final flatWords = _flatten(words);
  final flatExact = _flatten(exact);
  return _ShelfImage(
    paths: paths,
    ids: ids,
    types: types,
    fileOf: fileOf,
    offsets: offsets,
    lengths: lengths,
    flags: flags,
    groupOf: groupOf,
    groupLabels: groupLabels,
    facetKeys: facetKeys,
    words: flatWords.keys,
    wordStarts: flatWords.starts,
    wordPostings: flatWords.postings,
    exactKeys: flatExact.keys,
    exactStarts: flatExact.starts,
    exactPostings: flatExact.postings,
    episodes: episodes,
    folders: folders,
    titleCategories: titleCategories,
    categoryLabels: categoryLabels,
    plans: plans,
    settingsToken: token,
  );
}

// 2: title keys drop bracketed tags and trailing separators before the
// year, so copies of one film share a key.
const _indexVersion = 2;

String catalogSectionIndexPath(String sectionPath) => '$sectionPath.idx';

String _sectionFoldersPath(String sectionPath) => '$sectionPath.folders';

class _IndexSink {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  void i32s(List<int> values) {
    u32(values.length);
    if (values.isEmpty) return;
    final data = ByteData(values.length * 4);
    for (var i = 0; i < values.length; i++) {
      data.setInt32(i * 4, values[i], Endian.little);
    }
    _builder.add(data.buffer.asUint8List());
  }

  void str(String value) {
    final encoded = utf8.encode(value);
    u32(encoded.length);
    if (encoded.isNotEmpty) _builder.add(encoded);
  }

  void strs(List<String> values) {
    u32(values.length);
    for (final value in values) {
      str(value);
    }
  }

  Uint8List take() => _builder.takeBytes();
}

class _IndexCursor {
  _IndexCursor(this.bytes) : data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData data;
  int at = 0;

  void _need(int count) {
    if (at + count > bytes.length) {
      throw const FormatException('indice incompleto');
    }
  }

  int u32() {
    _need(4);
    final value = data.getUint32(at, Endian.little);
    at += 4;
    return value;
  }

  List<int> i32s() {
    final count = u32();
    _need(count * 4);
    final values = List<int>.filled(count, 0, growable: true);
    for (var i = 0; i < count; i++) {
      values[i] = data.getInt32(at, Endian.little);
      at += 4;
    }
    return values;
  }

  String str() {
    final count = u32();
    _need(count);
    final value = utf8.decode(bytes.sublist(at, at + count));
    at += count;
    return value;
  }

  List<String> strs() {
    final count = u32();
    return [for (var i = 0; i < count; i++) str()];
  }
}

void _writePlan(_IndexSink out, ShelfPlan plan) {
  out.i32s(plan.channels);
  out.i32s(plan.catalog);
  out.strs(plan.labels);
  out.u32(plan.groupSlots.length);
  for (final group in plan.groupSlots) {
    out.i32s(group);
  }
  out.i32s(plan.recent);
  out.i32s(plan.alphabetical);
}

ShelfPlan _readPlan(_IndexCursor cursor) {
  final channels = cursor.i32s();
  final catalog = cursor.i32s();
  final labels = cursor.strs();
  final groupCount = cursor.u32();
  final groupSlots = [for (var i = 0; i < groupCount; i++) cursor.i32s()];
  return ShelfPlan(
    channels: channels,
    catalog: catalog,
    labels: labels,
    groupSlots: groupSlots,
    recent: cursor.i32s(),
    alphabetical: cursor.i32s(),
  );
}

void _writeStringIntList(_IndexSink out, Map<String, List<int>> values) {
  out.u32(values.length);
  for (final entry in values.entries) {
    out.str(entry.key);
    out.i32s(entry.value);
  }
}

Map<String, List<int>> _readStringIntList(_IndexCursor cursor) {
  final count = cursor.u32();
  return {for (var i = 0; i < count; i++) cursor.str(): cursor.i32s()};
}

void _writeStringInt(_IndexSink out, Map<String, int> values) {
  out.u32(values.length);
  for (final entry in values.entries) {
    out.str(entry.key);
    out.u32(entry.value);
  }
}

Map<String, int> _readStringInt(_IndexCursor cursor) {
  final count = cursor.u32();
  return {for (var i = 0; i < count; i++) cursor.str(): cursor.u32()};
}

void _writeStringStrings(_IndexSink out, Map<String, List<String>> values) {
  out.u32(values.length);
  for (final entry in values.entries) {
    out.str(entry.key);
    out.strs(entry.value);
  }
}

Map<String, List<String>> _readStringStrings(_IndexCursor cursor) {
  final count = cursor.u32();
  return {for (var i = 0; i < count; i++) cursor.str(): cursor.strs()};
}

/// Writes the already built section index beside [sectionPath]. The synthetic
/// folder rows are copied to a sidecar that survives the temporary work dir.
void _writeSectionIndex(String sectionPath, _ShelfImage piece) {
  final section = File(sectionPath);
  if (!section.existsSync()) return;
  final sectionLength = section.lengthSync();
  if (sectionLength < 0 || sectionLength > 0xFFFFFFFF) return;
  final foldersPath = _sectionFoldersPath(sectionPath);
  final foldersSource = piece.paths.length > 1 ? piece.paths[1] : null;
  var foldersLength = 0;
  if (foldersSource != null && File(foldersSource).existsSync()) {
    if (foldersSource != foldersPath) {
      File(foldersSource).copySync(foldersPath);
    }
    foldersLength = File(foldersPath).lengthSync();
    if (foldersLength > 0xFFFFFFFF) return;
  } else {
    final previous = File(foldersPath);
    if (previous.existsSync()) previous.deleteSync();
  }
  final out = _IndexSink()
    ..u32(0x53545649)
    ..u32(_indexVersion)
    ..u32(sectionLength)
    ..u32(foldersLength)
    ..str(piece.settingsToken)
    ..strs(piece.ids)
    ..i32s(piece.types)
    ..i32s(piece.fileOf)
    ..i32s(piece.offsets)
    ..i32s(piece.lengths)
    ..i32s(piece.flags)
    ..i32s(piece.groupOf)
    ..strs(piece.groupLabels)
    ..strs(piece.facetKeys)
    ..strs(piece.words)
    ..i32s(piece.wordStarts)
    ..i32s(piece.wordPostings)
    ..strs(piece.exactKeys)
    ..i32s(piece.exactStarts)
    ..i32s(piece.exactPostings);
  _writeStringIntList(out, piece.episodes);
  _writeStringInt(out, piece.folders);
  _writeStringStrings(out, piece.titleCategories);
  _writeStringStrings(out, piece.categoryLabels);
  out.u32(piece.plans.length);
  for (final entry in piece.plans.entries) {
    out.str(entry.key);
    _writePlan(out, entry.value);
  }
  File(catalogSectionIndexPath(sectionPath)).writeAsBytesSync(out.take());
}

_ShelfImage? _readSectionIndex(String sectionPath, String token) {
  final index = File(catalogSectionIndexPath(sectionPath));
  final section = File(sectionPath);
  if (!index.existsSync() || !section.existsSync()) return null;
  final sectionLength = section.lengthSync();
  try {
    final cursor = _IndexCursor(index.readAsBytesSync());
    if (cursor.u32() != 0x53545649 || cursor.u32() != _indexVersion) {
      return null;
    }
    final storedLength = cursor.u32();
    final foldersLength = cursor.u32();
    final storedToken = cursor.str();
    if (storedLength != sectionLength || storedToken != token) return null;
    final foldersPath = _sectionFoldersPath(sectionPath);
    final foldersFile = File(foldersPath);
    if (foldersLength == 0) {
      if (foldersFile.existsSync()) return null;
    } else if (!foldersFile.existsSync() ||
        foldersFile.lengthSync() != foldersLength) {
      return null;
    }
    final paths = foldersLength == 0
        ? <String>[sectionPath]
        : <String>[sectionPath, foldersPath];
    final ids = cursor.strs();
    final image = _ShelfImage(
      paths: paths,
      ids: ids,
      types: cursor.i32s(),
      fileOf: cursor.i32s(),
      offsets: cursor.i32s(),
      lengths: cursor.i32s(),
      flags: cursor.i32s(),
      groupOf: cursor.i32s(),
      groupLabels: cursor.strs(),
      facetKeys: cursor.strs(),
      words: cursor.strs(),
      wordStarts: cursor.i32s(),
      wordPostings: cursor.i32s(),
      exactKeys: cursor.strs(),
      exactStarts: cursor.i32s(),
      exactPostings: cursor.i32s(),
      episodes: _readStringIntList(cursor),
      folders: _readStringInt(cursor),
      titleCategories: _readStringStrings(cursor),
      categoryLabels: _readStringStrings(cursor),
      plans: {
        for (var i = 0, n = cursor.u32(); i < n; i++)
          cursor.str(): _readPlan(cursor),
      },
      settingsToken: storedToken,
    );
    if (cursor.at != cursor.bytes.length) return null;
    if (image.ids.length != image.offsets.length ||
        image.fileOf.length != image.ids.length) {
      return null;
    }
    return image;
  } catch (_) {
    return null;
  }
}

/// Shared mask. Pages keep the same group objects; a verdict only moves this.
class CatalogVisibility {
  Uint8List mask = Uint8List(0);
  int stamp = 0;

  void setMask(Uint8List value) {
    mask = value;
    stamp++;
  }

  bool shows(int slot) => slot < mask.length && mask[slot] == 1;
}

/// Indexed local catalog. The provider keeps this object, the slot lists and
/// the filters. Titles and playback addresses stay in the section file and are
/// read a few dozen at a time. A new section is appended; the others stay.
class CatalogShelf implements CatalogChannelSource {
  CatalogShelf._(this._image, this.generation);

  static bool forbidDiskReads = false;

  /// Counts title-file reads so a test can see a full scan.
  static int diskReads = 0;

  factory CatalogShelf.empty() => CatalogShelf._(
    _ShelfImage(
      paths: const [],
      ids: const [],
      types: const [],
      fileOf: const [],
      offsets: const [],
      lengths: const [],
      flags: const [],
      groupOf: const [],
      groupLabels: const [''],
      facetKeys: const [],
      words: const [],
      wordStarts: const [0],
      wordPostings: const [],
      exactKeys: const [],
      exactStarts: const [0],
      exactPostings: const [],
      episodes: const {},
      folders: const {},
      titleCategories: const {},
      categoryLabels: const {},
      plans: const {},
      settingsToken: '',
    ),
    0,
  );

  static Future<CatalogShelf> fromChannels(
    List<Channel> channels, {
    required Map<String, List<String>> hidden,
    required List<CustomCategory> custom,
    required Map<String, List<String>> order,
    int generation = 1,
  }) async {
    if (channels.isEmpty) return CatalogShelf.empty();
    final directory = Directory.systemTemp.createTempSync('stv_shelf_').path;
    final rows = channels;
    final image = await Isolate.run(
      () => _buildShelfFromChannels(directory, rows, hidden, custom, order),
    );
    return CatalogShelf._(image, generation);
  }

  static Future<CatalogShelf> fromSectionFiles(
    List<String> sectionPaths, {
    required Map<String, List<String>> hidden,
    required List<CustomCategory> custom,
    required Map<String, List<String>> order,
    int generation = 1,
  }) async {
    if (!sectionPaths.any((path) => File(path).existsSync())) {
      return CatalogShelf.empty();
    }
    final directory = Directory.systemTemp.createTempSync('stv_shelf_').path;
    final paths = sectionPaths;
    final image = await Isolate.run(
      () => _buildShelfFromFiles(paths, directory, hidden, custom, order),
    );
    return CatalogShelf._(image, generation);
  }

  _ShelfImage _image;
  final int generation;
  final List<_ShelfImage> _pieces = [];
  String? _workDir;
  final List<RandomAccessFile?> _files = [];
  final LinkedHashMap<int, Channel> _window = LinkedHashMap();
  static const _windowLimit = 640;

  int get length => _image.ids.length;
  bool get isEmpty => _image.ids.isEmpty;
  String get settingsToken => _image.settingsToken;
  String? get storagePath => _image.paths.isEmpty ? null : _image.paths.first;

  /// Section files already indexed, in publication order.
  List<String> get sectionPaths => [
    for (final piece in _pieces)
      if (piece.paths.isNotEmpty) piece.paths.first,
  ];

  Map<String, List<String>> get titleCategories => _image.titleCategories;

  List<String> categoryLabels(ContentType type) =>
      _image.categoryLabels[type.name] ?? const [];

  ShelfPlan? plan(ContentType type) => _image.plans[type.name];

  bool isAdultSlot(int slot) => (_image.flags[slot] & shelfFlagAdult) != 0;

  bool isBannedSlot(int slot) => (_image.flags[slot] & shelfFlagBanned) != 0;

  bool isKidsSlot(int slot) => (_image.flags[slot] & shelfFlagKids) != 0;

  void setKidsFlag(int slot, bool allowed) {
    if (allowed) {
      _image.flags[slot] |= shelfFlagKids;
    } else {
      _image.flags[slot] &= ~shelfFlagKids;
    }
  }

  /// File that holds this slot. Section slots stay on the saved section file.
  String pathOfSlot(int slot) => _image.paths[_image.fileOf[slot]];

  String groupAt(int slot) => _image.groupLabels[_image.groupOf[slot]];

  String facetKeyAt(int slot) => _image.facetKeys[slot];

  /// Pairs facet keys already stored on the shelf with display names read
  /// off the UI isolate. Does not open a title.
  List<({String key, String title})> kidsIndexPairs(
    List<String> ids,
    List<String> names,
  ) {
    final out = <({String key, String title})>[];
    final count = ids.length < names.length ? ids.length : names.length;
    for (var i = 0; i < count; i++) {
      final slot = _slotOf(ids[i]);
      if (slot == null) continue;
      final key = _image.facetKeys[slot];
      if (key.isEmpty) continue;
      out.add((key: key, title: names[i]));
    }
    return out;
  }

  bool isFolderSlot(int slot) => (_image.flags[slot] & shelfFlagFolder) != 0;

  String idAt(int slot) => _image.ids[slot];

  /// [slots] in [order], read and compared off the UI isolate.
  Future<List<int>> sortSlots(List<int> slots, CatalogSort order) {
    if (order == CatalogSort.provider ||
        slots.length < 2 ||
        _image.paths.isEmpty) {
      return Future.value(List<int>.of(slots));
    }
    return _sortSlotsInIsolate(
      _image.paths,
      _image.fileOf,
      _image.offsets,
      _image.lengths,
      List<int>.of(slots),
      order,
    );
  }

  int? slotOfId(String id) => _slotOf(id);

  @override
  Channel readSlot(int slot) {
    diskReads++;
    if (forbidDiskReads) {
      throw StateError('lettura del titolo durante la pubblicazione');
    }
    final cached = _window.remove(slot);
    if (cached != null) {
      _window[slot] = cached;
      return cached;
    }
    final fileIndex = _image.fileOf[slot];
    while (_files.length <= fileIndex) {
      _files.add(null);
    }
    final handle = _files[fileIndex] ??= File(_image.paths[fileIndex])
        .openSync();
    handle.setPositionSync(_image.offsets[slot]);
    final bytes = handle.readSync(_image.lengths[slot]);
    final decoded = jsonDecode(utf8.decode(bytes));
    final channel = Channel.fromMap((decoded as Map).cast<String, dynamic>());
    _window[slot] = channel;
    while (_window.length > _windowLimit) {
      _window.remove(_window.keys.first);
    }
    return channel;
  }

  Channel? readId(String id) {
    final slot = _slotOf(id);
    if (slot == null) return null;
    return readSlot(slot);
  }

  int? _slotOf(String id) {
    // Ids are unique in a published catalog. A linear scan would bring back
    // the bottleneck, so the first adoption builds the lookup below.
    return _idIndex[id];
  }

  Map<String, int>? _idIndexCache;

  Map<String, int> get _idIndex => _idIndexCache ??= {
    for (var i = 0; i < _image.ids.length; i++) _image.ids[i]: i,
  };

  List<int> slotsOfType(ContentType type) {
    final index = type.index;
    return [
      for (var i = 0; i < _image.types.length; i++)
        if (_image.types[i] == index) i,
    ];
  }

  List<Channel> episodesOf(Channel series) {
    final key = series.seriesKey?.isNotEmpty == true
        ? series.seriesKey!
        : series.id;
    final slots = _image.episodes[key] ?? const <int>[];
    return [for (final slot in slots) readSlot(slot)];
  }

  int? folderSlot(String key) => _image.folders[key];

  int typeIndexAt(int slot) => _image.types[slot];

  List<Channel> materialize() => [
    for (var i = 0; i < length; i++)
      if ((_image.flags[i] & shelfFlagSynthetic) == 0) readSlot(i),
  ];

  /// Indexes [path] alone and appends that fragment. The same path replaces
  /// its previous fragment. A different settings token is left to [retune].
  Future<void> appendSection(
    String path, {
    required Map<String, List<String>> hidden,
    required List<CustomCategory> custom,
    required Map<String, List<String>> order,
  }) async {
    if (!File(path).existsSync()) return;
    final token = shelfSettingsToken(
      hidden: hidden,
      custom: custom,
      order: order,
    );
    final directory = _workDir ??= Directory.systemTemp
        .createTempSync('stv_shelf_')
        .path;
    final image = await Isolate.run(() {
      final built = _sectionImage(path, directory, hidden, custom, order);
      if (built != null) {
        try {
          _writeSectionIndex(path, built);
        } catch (_) {}
      }
      return built;
    });
    if (image == null) return;
    _pieces.removeWhere(
      (piece) => piece.paths.isNotEmpty && piece.paths.first == path,
    );
    _pieces.add(image);
    _releaseHandles();
    _image = _mergePieces(_pieces, token);
  }

  /// Publishes [path] from the saved index. Returns false when the index is
  /// missing, stale, or built for another settings token.
  Future<bool> adoptIndex(String path, {required String token}) async {
    if (!File(path).existsSync()) return false;
    final image = await Isolate.run(() => _readSectionIndex(path, token));
    if (image == null) return false;
    _pieces.removeWhere(
      (piece) => piece.paths.isNotEmpty && piece.paths.first == path,
    );
    _pieces.add(image);
    _releaseHandles();
    _image = _mergePieces(_pieces, token);
    return true;
  }

  void _releaseHandles() {
    for (final file in _files) {
      try {
        file?.closeSync();
      } catch (_) {}
    }
    _files.clear();
    _window.clear();
    _idIndexCache = null;
  }

  Future<CatalogShelf> retune({
    required Map<String, List<String>> hidden,
    required List<CustomCategory> custom,
    required Map<String, List<String>> order,
    required int generation,
  }) async {
    final token = shelfSettingsToken(
      hidden: hidden,
      custom: custom,
      order: order,
    );
    if (token == settingsToken || (_image.paths.isEmpty && _pieces.isEmpty)) {
      return this;
    }
    if (_pieces.isNotEmpty) {
      final paths = [
        for (final piece in _pieces)
          if (piece.paths.isNotEmpty) piece.paths.first,
      ];
      return CatalogShelf.fromSectionFiles(
        paths,
        hidden: hidden,
        custom: custom,
        order: order,
        generation: generation,
      );
    }
    final source = _image.paths.first;
    final directory = Directory.systemTemp.createTempSync('stv_shelf_').path;
    final image = await Isolate.run(
      () => _buildShelfFromPlainBody(source, directory, hidden, custom, order),
    );
    return CatalogShelf._(image, generation);
  }

  Future<void> warmNames(
    ContentType type,
    void Function(List<String> ids, List<String> names) apply,
  ) async {
    final plan = this.plan(type);
    if (plan == null || _image.paths.isEmpty || plan.alphabetical.isEmpty) {
      return;
    }
    final slots = plan.alphabetical;
    final namesBySlot = <int, String>{};
    final byFile = <int, List<int>>{};
    for (final slot in slots) {
      if (slot < 0 || slot >= _image.fileOf.length) continue;
      (byFile[_image.fileOf[slot]] ??= <int>[]).add(slot);
    }
    for (final entry in byFile.entries) {
      if (entry.key < 0 || entry.key >= _image.paths.length) continue;
      final path = _image.paths[entry.key];
      final offsets = _image.offsets;
      final lengths = _image.lengths;
      final mine = entry.value;
      final part = await Isolate.run(
        () => readShelfDisplayNames(path, offsets, lengths, mine),
      );
      for (var i = 0; i < mine.length && i < part.length; i++) {
        namesBySlot[mine[i]] = part[i];
      }
    }
    apply(
      [for (final slot in slots) _image.ids[slot]],
      [for (final slot in slots) namesBySlot[slot] ?? ''],
    );
  }

  /// [flags] of every title name in [slots], computed off the UI isolate.
  /// Name filters (4K, platform tags) read each title, and doing that in a
  /// build froze the TV for seconds.
  Future<Map<int, int>> nameFlags(
    List<int> slots,
    int Function(String name) flags,
  ) async {
    final out = <int, int>{};
    if (_image.paths.isEmpty || slots.isEmpty) return out;
    final byFile = <int, List<int>>{};
    for (final slot in slots) {
      if (slot < 0 || slot >= _image.fileOf.length) continue;
      (byFile[_image.fileOf[slot]] ??= <int>[]).add(slot);
    }
    for (final entry in byFile.entries) {
      if (entry.key < 0 || entry.key >= _image.paths.length) continue;
      final path = _image.paths[entry.key];
      final offsets = _image.offsets;
      final lengths = _image.lengths;
      final mine = entry.value;
      out.addAll(
        await Isolate.run(
          () => readShelfNameFlags(path, offsets, lengths, mine, flags),
        ),
      );
    }
    return out;
  }

  List<int> searchSlots(String query) {
    final tokens = query
        .toLowerCase()
        .split(_wordSplit)
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) return const [];
    Set<int>? matched;
    for (final token in tokens) {
      final hits = _prefixHits(token);
      if (hits.isEmpty) return const [];
      matched = matched == null ? hits : matched.intersection(hits);
      if (matched.isEmpty) return const [];
    }
    return matched!.toList(growable: false);
  }

  /// Channel ids of [typeIndex] that the prefix index hits inside [among].
  /// The walk stays on the posting lists already in memory.
  Set<String> idsMatching(
    String query, {
    required int typeIndex,
    required Set<String> among,
  }) {
    if (among.isEmpty) return const {};
    final out = <String>{};
    for (final slot in searchSlots(query)) {
      if (slot < 0 || slot >= _image.types.length) continue;
      if (_image.types[slot] != typeIndex) continue;
      final id = _image.ids[slot];
      if (!among.contains(id)) continue;
      out.add(id);
      if (out.length == among.length) break;
    }
    return out;
  }

  /// Live channel identity (id, name, guide ids) read off the UI isolate.
  Future<List<Map<String, String>>> liveIdentities() {
    if (isEmpty || _image.paths.isEmpty) return Future.value(const []);
    final paths = _image.paths;
    final fileOf = _image.fileOf;
    final offsets = _image.offsets;
    final lengths = _image.lengths;
    final types = _image.types;
    final live = ContentType.live.index;
    return Isolate.run(
      () => _readLiveIdentities(paths, fileOf, offsets, lengths, types, live),
    );
  }

  Set<int> _prefixHits(String token) {
    final words = _image.words;
    var index = _lowerBound(words, token);
    final hits = <int>{};
    final starts = _image.wordStarts;
    final postings = _image.wordPostings;
    while (index < words.length && words[index].startsWith(token)) {
      for (var i = starts[index]; i < starts[index + 1]; i++) {
        hits.add(postings[i]);
      }
      index++;
    }
    return hits;
  }

  List<int> exactSlots(String titleKey) {
    final keys = _image.exactKeys;
    final index = _lowerBound(keys, titleKey);
    if (index >= keys.length || keys[index] != titleKey) return const [];
    final start = _image.exactStarts[index];
    final end = _image.exactStarts[index + 1];
    return _image.exactPostings.sublist(start, end);
  }

  void close() {
    _releaseHandles();
    final directory = _workDir;
    if (directory != null) {
      try {
        Directory(directory).deleteSync(recursive: true);
      } catch (_) {}
      _workDir = null;
    }
  }
}

/// Catalog rows addressed by slot. A tile reads its title the first time it
/// is built; publishing the shelf does not build one entry per title.
class SlotEntryList extends ListBase<CatalogEntry> {
  SlotEntryList(this.source, this.slots, {this.visibility});

  final CatalogChannelSource source;
  final List<int> slots;
  final CatalogVisibility? visibility;
  int _stamp = -1;
  List<int> _visible = const [];

  List<int> get _shown {
    final current = visibility;
    if (current == null) return slots;
    if (_stamp != current.stamp) {
      _stamp = current.stamp;
      _visible = [
        for (final slot in slots)
          if (current.shows(slot)) slot,
      ];
    }
    return _visible;
  }

  @override
  int get length => _shown.length;

  @override
  set length(int newLength) =>
      throw UnsupportedError('catalogo in sola lettura');

  @override
  CatalogEntry operator [](int index) =>
      CatalogEntry.slot(_shown[index], source);

  @override
  void operator []=(int index, CatalogEntry value) =>
      throw UnsupportedError('catalogo in sola lettura');
}

List<Map<String, String>> _readLiveIdentities(
  List<String> paths,
  List<int> fileOf,
  List<int> offsets,
  List<int> lengths,
  List<int> types,
  int liveType,
) {
  final files = <int, RandomAccessFile>{};
  try {
    final out = <Map<String, String>>[];
    for (var i = 0; i < types.length && i < offsets.length; i++) {
      if (types[i] != liveType || lengths[i] <= 0) continue;
      final fileIndex = fileOf[i];
      if (fileIndex < 0 || fileIndex >= paths.length) continue;
      final handle = files[fileIndex] ??= File(paths[fileIndex]).openSync();
      handle.setPositionSync(offsets[i]);
      final decoded = jsonDecode(utf8.decode(handle.readSync(lengths[i])));
      if (decoded is! Map) continue;
      final id = decoded['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final row = <String, String>{
        'id': id,
        'name': decoded['name']?.toString() ?? '',
      };
      final tvgId = decoded['tvg_id']?.toString();
      final tvgName = decoded['tvg_name']?.toString();
      if (tvgId != null && tvgId.isNotEmpty) row['tvgId'] = tvgId;
      if (tvgName != null && tvgName.isNotEmpty) row['tvgName'] = tvgName;
      out.add(row);
    }
    return out;
  } finally {
    for (final file in files.values) {
      try {
        file.closeSync();
      } catch (_) {}
    }
  }
}

/// List of titles addressed by shelf slots. Indexing a row reads that row
/// only; the rest stays on disk.
class ShelfChannelList extends ListBase<Channel> {
  ShelfChannelList(this.shelf, this.slots, {this.visibility});

  final CatalogShelf shelf;
  final List<int> slots;
  final CatalogVisibility? visibility;
  int _stamp = -1;
  List<int> _visible = const [];

  /// The same titles in [order]. The list stays backed by the shelf, so
  /// sorting never copies the shelf into the isolate.
  Future<ShelfChannelList> sorted(CatalogSort order) async => ShelfChannelList(
    shelf,
    await shelf.sortSlots(_shown, order),
    visibility: visibility,
  );

  List<int> get _shown {
    final current = visibility;
    if (current == null) return slots;
    if (_stamp != current.stamp) {
      _stamp = current.stamp;
      _visible = [
        for (final slot in slots)
          if (current.shows(slot)) slot,
      ];
    }
    return _visible;
  }

  /// Ids of the visible slots. Does not open the title file.
  Set<String> get ids => {for (final slot in _shown) shelf.idAt(slot)};

  int indexOfId(String id) {
    final slot = shelf.slotOfId(id);
    if (slot == null) return -1;
    final shown = _shown;
    for (var i = 0; i < shown.length; i++) {
      if (shown[i] == slot) return i;
    }
    return -1;
  }

  /// Title [offset] steps from [id] within its group, or within the whole
  /// list when the group holds only that title. Walks the index only: the
  /// player asks on every rebuild and reading each title froze it for seconds.
  Channel? adjacentInGroup(String id, int offset) {
    final current = shelf.slotOfId(id);
    if (current == null) return null;
    final shown = _shown;
    final group = shelf.groupAt(current);
    final sameGroup = [
      for (final slot in shown)
        if (shelf.groupAt(slot) == group) slot,
    ];
    final pool = sameGroup.length > 1 ? sameGroup : shown;
    final index = pool.indexOf(current);
    final target = index + offset;
    if (index < 0 || target < 0 || target >= pool.length) return null;
    return shelf.readSlot(pool[target]);
  }

  ShelfChannelList whereIds(Set<String> wanted) {
    return ShelfChannelList(shelf, [
      for (final slot in _shown)
        if (wanted.contains(shelf.idAt(slot))) slot,
    ]);
  }

  @override
  int get length => _shown.length;

  @override
  set length(int newLength) =>
      throw UnsupportedError('catalogo in sola lettura');

  @override
  Channel operator [](int index) => shelf.readSlot(_shown[index]);

  @override
  void operator []=(int index, Channel value) =>
      throw UnsupportedError('catalogo in sola lettura');
}
