import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/channel.dart';
import '../models/tmdb_item.dart';

/// Mirrors favorites to the `cloud_favorites` table, keyed on the device's
/// 8-character sync code (the app has no accounts, like the cloud sync and
/// profiles). The device stays the source of truth; the cloud copy lets the
/// list survive a reinstall and appear on every paired device.
class CloudFavoritesService {
  CloudFavoritesService(this._client);

  final SupabaseClient _client;

  static const _table = 'cloud_favorites';

  /// Loads every favorite stored for [syncCode]. Returns an empty list when
  /// there is nothing stored or the request fails, so the local data is kept.
  Future<List<Map<String, dynamic>>> load(String syncCode) async {
    if (syncCode.isEmpty) return const [];
    try {
      final rows = await _client
          .from(_table)
          .select('item_key, item_kind, payload')
          .eq('sync_code', syncCode);
      return rows.map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> addChannel(String syncCode, Channel channel) =>
      _upsert(syncCode, channel.id, 'channel', channel.toMap());

  Future<void> addTmdb(String syncCode, TmdbItem item) =>
      _upsert(syncCode, item.key, 'tmdb', item.toJson());

  Future<void> remove(String syncCode, String itemKey, String kind) async {
    if (syncCode.isEmpty) return;
    try {
      await _client
          .from(_table)
          .delete()
          .eq('sync_code', syncCode)
          .eq('item_key', itemKey)
          .eq('item_kind', kind);
    } catch (_) {
      // Best effort: the local copy is already updated.
    }
  }

  /// Pushes every local favorite, so enabling sync uploads the current list.
  Future<void> replaceAll({
    required String syncCode,
    required Iterable<Channel> channels,
    required Iterable<TmdbItem> tmdbItems,
  }) async {
    if (syncCode.isEmpty) return;
    try {
      final rows = <Map<String, dynamic>>[
        for (final c in channels)
          _row(syncCode, c.id, 'channel', c.toMap()),
        for (final t in tmdbItems) _row(syncCode, t.key, 'tmdb', t.toJson()),
      ];
      if (rows.isNotEmpty) {
        await _client
            .from(_table)
            .upsert(rows, onConflict: 'sync_code,item_key,item_kind');
      }
    } catch (_) {
      // Best effort: local data is unaffected.
    }
  }

  Future<void> _upsert(
    String syncCode,
    String itemKey,
    String kind,
    Map<String, dynamic> payload,
  ) async {
    if (syncCode.isEmpty) return;
    try {
      await _client.from(_table).upsert(
            _row(syncCode, itemKey, kind, payload),
            onConflict: 'sync_code,item_key,item_kind',
          );
    } catch (_) {
      // Best effort: the local copy is already updated.
    }
  }

  Map<String, dynamic> _row(
    String syncCode,
    String itemKey,
    String kind,
    Map<String, dynamic> payload,
  ) =>
      {
        'sync_code': syncCode,
        'item_key': itemKey,
        'item_kind': kind,
        'payload': payload,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}
