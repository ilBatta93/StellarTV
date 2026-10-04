import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/channel.dart';

/// Keeps the last complete playlist on disk so catalog screens can render
/// immediately while the provider refreshes the current version.
class CatalogCacheService {
  int _hash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  Future<File> _file(String accountKey) async {
    final directory = await getApplicationSupportDirectory();
    return File(
      '${directory.path}/stellartv_catalog_v1_${_hash(accountKey)}.json',
    );
  }

  Future<List<Channel>> read(String accountKey) async {
    try {
      final file = await _file(accountKey);
      if (!await file.exists()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => Channel.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> write(String accountKey, List<Channel> channels) async {
    if (channels.isEmpty) return;
    try {
      final file = await _file(accountKey);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode([
        for (final channel in channels) channel.toJson(),
      ]));
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    } catch (_) {
      // A cache write must never affect playback or catalog refresh.
    }
  }

  Future<void> clear(String accountKey) async {
    try {
      final file = await _file(accountKey);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}