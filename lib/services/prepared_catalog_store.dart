import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/custom_category.dart';
import 'catalog_builder.dart';
import 'catalog_preparation.dart';

/// Device-local copy of the prepared catalog structure (category order,
/// newest and alphabetical lists) stored as id lists. A normal launch with an
/// unchanged playlist and unchanged category settings restores it in one
/// linear pass instead of grouping and sorting the whole playlist again; any
/// change in the playlist or settings changes the signature and the full
/// preparation runs as before. Nothing here leaves the device.
class PreparedCatalogStore {
  PreparedCatalogStore._();
  static final instance = PreparedCatalogStore._();

  static const _version = 1;

  static int _hash(int hash, String value) {
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  /// Signature of everything the prepared structure depends on.
  static Future<String> signature({
    required List<Channel> snapshot,
    required ContentType type,
    required Set<String> hidden,
    required List<CustomCategory> custom,
    required List<String> order,
    required CatalogYield yieldWork,
  }) async {
    var hash = 0x811c9dc5;
    var count = 0;
    for (final c in snapshot) {
      if (c.type == type) {
        count++;
        hash = _hash(hash, c.id);
        hash = _hash(hash, c.name);
        hash = _hash(hash, c.group);
        hash = _hash(hash, '${c.addedAt}|${c.isSeriesFolder}');
      }
      await yieldWork.step();
    }
    final settings = [
      ...(hidden.toList()..sort()),
      '|',
      for (final c in custom) '${c.name}:${c.itemIds.join(',')}',
      '|',
      ...order,
    ].join('\u0001');
    return 'v$_version:${type.name}:$count:$hash:${_hash(0x811c9dc5, settings)}';
  }

  /// Id-only form of a prepared catalog.
  static Map<String, Object> encode(String signature, PreparedCatalog p,
      {Map<int, int>? genreCounts}) => {
    'sig': signature,
    'catalog': [for (final c in p.catalog) c.id],
    'groups': [
      for (final g in p.groups)
        [
          g.label,
          [for (final e in g.entries) e.primary.id],
        ],
    ],
    'recent': [for (final e in p.recent) e.primary.id],
    'all': [for (final e in p.all) e.primary.id],
    if (genreCounts != null)
      'genreCounts': {for (final e in genreCounts.entries) '${e.key}': e.value},
  };

  static Map<int, int>? genreCounts(Map<String, dynamic> data) {
    final raw = data['genreCounts'];
    if (raw is! Map) return null;
    final result = <int, int>{};
    for (final entry in raw.entries) {
      final id = int.tryParse('${entry.key}');
      final value = entry.value;
      if (id == null || value is! int || value < 0) return null;
      result[id] = value;
    }
    return result;
  }

  /// Rebuilds a prepared catalog from its id form, or null when anything no
  /// longer resolves (then the caller prepares from scratch).
  static Future<PreparedCatalog?> restore(
    Map<String, dynamic> data,
    String signature,
    List<Channel> snapshot,
    ContentType type,
    CatalogYield yieldWork,
  ) async {
    if (data['sig'] != signature) return null;
    final channels = <Channel>[];
    final byId = <String, Channel>{};
    for (final c in snapshot) {
      if (c.type == type) {
        channels.add(c);
        byId[c.id] = c;
      }
      await yieldWork.step();
    }
    final entries = <String, CatalogEntry>{};
    CatalogEntry? entry(Object? id) {
      final c = byId[id];
      if (c == null) return null;
      return entries[c.id] ??= CatalogEntry(primary: c, variants: [c]);
    }

    final catalog = <Channel>[];
    for (final id in (data['catalog'] as List? ?? const [])) {
      final c = byId[id];
      if (c == null) return null;
      catalog.add(c);
      await yieldWork.step();
    }
    final groups = <CatalogGroup>[];
    for (final g in (data['groups'] as List? ?? const [])) {
      if (g is! List || g.length != 2 || g[1] is! List) return null;
      final list = <CatalogEntry>[];
      for (final id in g[1] as List) {
        final e = entry(id);
        if (e == null) return null;
        list.add(e);
        await yieldWork.step();
      }
      groups.add(CatalogGroup(label: '${g[0]}', entries: list));
    }
    Future<List<CatalogEntry>?> list(Object? raw) async {
      final out = <CatalogEntry>[];
      for (final id in (raw as List? ?? const [])) {
        final e = entry(id);
        if (e == null) return null;
        out.add(e);
        await yieldWork.step();
      }
      return out;
    }

    final recent = await list(data['recent']);
    final all = await list(data['all']);
    if (recent == null || all == null) return null;
    final isSeries = type == ContentType.series || type == ContentType.anime;
    return PreparedCatalog(
      channels,
      isSeries ? catalog : channels,
      groups,
      recent,
      all,
    );
  }

  int _fileHash(String value) => _hash(0x811c9dc5, value);

  Future<String> _path(String accountKey, ContentType type) async {
    final dir = (await getApplicationSupportDirectory()).path;
    return '$dir/stellartv_prepared_v${_version}_${_fileHash(accountKey)}_${type.name}.json';
  }

  Future<Map<String, dynamic>?> read(
    String accountKey,
    ContentType type,
  ) async {
    try {
      final path = await _path(accountKey, type);
      return await Isolate.run(() {
        final file = File(path);
        if (!file.existsSync()) return null;
        final decoded = jsonDecode(file.readAsStringSync());
        return decoded is Map ? decoded.cast<String, dynamic>() : null;
      });
    } catch (_) {
      return null;
    }
  }

  Future<void> write(
    String accountKey,
    ContentType type,
    String signature,
    PreparedCatalog prepared, {
    Map<int, int>? genreCounts,
  }
  ) async {
    try {
      final path = await _path(accountKey, type);
      final data = encode(signature, prepared, genreCounts: genreCounts);
      await Isolate.run(() {
        final tmp = File('$path.${DateTime.now().microsecondsSinceEpoch}.tmp');
        tmp.writeAsStringSync(jsonEncode(data), flush: true);
        tmp.renameSync(path);
      });
    } catch (_) {
      // A missing copy only means the next launch prepares from scratch.
    }
  }

  Future<void> clear(String accountKey) async {
    for (final type in ContentType.values) {
      try {
        final file = File(await _path(accountKey, type));
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }
}
