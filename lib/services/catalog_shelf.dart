import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/custom_category.dart';
import 'catalog_builder.dart';
import 'catalog_index_builder.dart' show catalogEntryKey, catalogTitleKey;
import 'catalog_preparation.dart';
import 'kids_content_service.dart';

/// Adult titles are flagged while the shelf is built, so the provider can
/// hide them without keeping the raw catalog.
const shelfFlagAdult = 1;
const shelfFlagFolder = 2;
const shelfFlagBanned = 4;
const shelfFlagSynthetic = 8;

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
    buffer.write('${category.type.name}:${category.name}:${category.itemIds.join(',')};');
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

  static ShelfPlan fromPrepared(PreparedCatalog prepared, Map<Channel, int> slotOf) {
    int slot(Channel channel) {
      final index = slotOf[channel];
      if (index == null) {
        throw StateError('Titolo preparato assente dallo scaffale');
      }
      return index;
    }

    List<int> entries(List<CatalogEntry> list) =>
        [for (final entry in list) slot(entry.primary)];

    return ShelfPlan(
      channels: [for (final channel in prepared.channels) slot(channel)],
      catalog: [for (final channel in prepared.catalog) slot(channel)],
      labels: [for (final group in prepared.groups) group.label],
      groupSlots: [
        for (final group in prepared.groups) entries(group.entries),
      ],
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
        : folders[channel.seriesKey ?? ''] ??
              folders[channel.id] ??
              slot;
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
      custom: [for (final category in custom) if (category.type == type) category],
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
  final token = shelfSettingsToken(hidden: hidden, custom: custom, order: order);
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

/// Indexed local catalog. The provider keeps this object, the slot lists and
/// the filters. Titles and playback addresses stay in the NDJSON body and are
/// read a few dozen at a time.
class CatalogShelf implements CatalogChannelSource {
  CatalogShelf._(this._image, this.generation);

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

  final _ShelfImage _image;
  final int generation;
  final List<RandomAccessFile?> _files = [];
  final LinkedHashMap<int, Channel> _window = LinkedHashMap();
  static const _windowLimit = 640;

  int get length => _image.ids.length;
  bool get isEmpty => _image.ids.isEmpty;
  String get settingsToken => _image.settingsToken;
  String? get storagePath => _image.paths.isEmpty ? null : _image.paths.first;
  Map<String, List<String>> get titleCategories => _image.titleCategories;

  List<String> categoryLabels(ContentType type) =>
      _image.categoryLabels[type.name] ?? const [];

  ShelfPlan? plan(ContentType type) => _image.plans[type.name];

  bool isAdultSlot(int slot) => (_image.flags[slot] & shelfFlagAdult) != 0;

  String groupAt(int slot) => _image.groupLabels[_image.groupOf[slot]];

  String facetKeyAt(int slot) => _image.facetKeys[slot];

  bool isFolderSlot(int slot) => (_image.flags[slot] & shelfFlagFolder) != 0;

  @override
  Channel readSlot(int slot) {
    final cached = _window.remove(slot);
    if (cached != null) {
      _window[slot] = cached;
      return cached;
    }
    final fileIndex = _image.fileOf[slot];
    while (_files.length <= fileIndex) {
      _files.add(null);
    }
    final handle = _files[fileIndex] ??= File(
      _image.paths[fileIndex],
    ).openSync();
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
    if (token == settingsToken || _image.paths.isEmpty) return this;
    final source = _image.paths.first;
    final directory = Directory.systemTemp.createTempSync('stv_shelf_').path;
    final image = await Isolate.run(
      () => _buildShelfFromPlainBody(source, directory, hidden, custom, order),
    );
    return CatalogShelf._(image, generation);
  }

  Future<void> warmNames(ContentType type, void Function(List<String> ids, List<String> names) apply) async {
    final plan = this.plan(type);
    final path = _image.paths.isEmpty ? null : _image.paths.first;
    if (plan == null || path == null || plan.alphabetical.isEmpty) return;
    final slots = plan.alphabetical;
    final offsets = _image.offsets;
    final lengths = _image.lengths;
    final ids = [for (final slot in slots) _image.ids[slot]];
    final names = await Isolate.run(
      () => readShelfDisplayNames(path, offsets, lengths, slots),
    );
    apply(ids, names);
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
    for (final file in _files) {
      try {
        file?.closeSync();
      } catch (_) {}
    }
    _files.clear();
    _window.clear();
  }
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
  ShelfChannelList(this.shelf, this.slots);

  final CatalogShelf shelf;
  final List<int> slots;

  @override
  int get length => slots.length;

  @override
  set length(int newLength) => throw UnsupportedError('catalogo in sola lettura');

  @override
  Channel operator [](int index) => shelf.readSlot(slots[index]);

  @override
  void operator []=(int index, Channel value) =>
      throw UnsupportedError('catalogo in sola lettura');
}
