import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/channel.dart';
import '../models/tmdb_item.dart';
import 'personal_vault.dart';
import 'sync_hooks.dart';

class FavoritesService {
  static Future<void> _eventQueue = Future<void>.value();
  static const _key = 'favorite_channels';
  static const _tmdbKey = 'favorite_tmdb_items';

  static Future<T> _serialized<T>(Future<T> Function() action) {
    final next = _eventQueue.then((_) => action());
    _eventQueue = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return next;
  }

  static Future<void> drainPendingWrites() => _eventQueue;

  Future<void> recordEvent(
    String key,
    bool deleted, {
    Map<String, dynamic>? payload,
  }) {
    return _serialized(() => _recordEvent(key, deleted, payload: payload));
  }

  Future<void> _recordEvent(
    String key,
    bool deleted, {
    Map<String, dynamic>? payload,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final events = PersonalVault.object(
      jsonDecode(prefs.getString('vault_favorite_events_v1') ?? '{}'),
    );
    final old = DateTime.tryParse(
      PersonalVault.object(events[key])['watched']?.toString() ?? '',
    );
    var now = DateTime.now().toUtc();
    if (old != null && !now.isAfter(old))
      now = old.add(const Duration(microseconds: 1));
    events[key] = {
      ...?payload,
      'deleted': deleted,
      'watched': now.toIso8601String(),
    };
    await prefs.setString('vault_favorite_events_v1', jsonEncode(events));
  }

  Future<void> applyEncrypted(Map<String, dynamic> snapshot) {
    return _serialized(() => _applyEncrypted(snapshot));
  }

  Future<void> _applyEncrypted(Map<String, dynamic> snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    final remote = PersonalVault.object(
      snapshot['profile_histories'],
    )[PersonalVault.favoriteLane];
    final local = PersonalVault.object(
      jsonDecode(prefs.getString('vault_favorite_events_v1') ?? '{}'),
    );
    final events = PersonalVault.mergeHistory(remote, local);
    final ids = (prefs.getStringList(_key) ?? []).toSet()
      ..addAll((snapshot['favorite_ids'] as List? ?? []).whereType<String>());
    final items = {for (final t in await getTmdbFavorites()) t.key: t.toJson()};
    for (final raw in snapshot['tmdb_favorites'] as List? ?? []) {
      final t = TmdbItem.tryParse(PersonalVault.object(raw));
      if (t != null) items[t.key] = t.toJson();
    }
    for (final e in events.entries) {
      final event = PersonalVault.object(e.value);
      if (e.key.startsWith('c:')) {
        if (event['deleted'] == true) {
          ids.remove(e.key.substring(2));
        } else {
          ids.add(e.key.substring(2));
        }
      }
      if (e.key.startsWith('t:')) {
        if (event['deleted'] == true) {
          items.remove(e.key.substring(2));
        } else {
          final t = TmdbItem.tryParse(event);
          if (t != null) items[t.key] = t.toJson();
        }
      }
    }
    await prefs.setStringList(_key, ids.toList());
    await prefs.setString(_tmdbKey, jsonEncode(items.values.toList()));
    await prefs.setString('vault_favorite_events_v1', jsonEncode(events));
  }

  Future<Set<String>> getFavoriteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    return list.toSet();
  }

  Future<Set<String>> toggleFavorite(Channel channel) => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_key) ?? []).toSet();
    if (!set.remove(channel.id)) set.add(channel.id);
    await _recordEvent('c:${channel.id}', !set.contains(channel.id));
    await prefs.setStringList(_key, set.toList());
    SyncHooks.settingsChanged();
    return set;
  });

  /// Explicit imports are additions, including IDs not in the local catalog.
  /// Do not use this for cloud pulls: those must retain remote event dates.
  Future<void> importFavorites(Iterable<String> ids, Iterable<TmdbItem> tmdb) =>
      _serialized(() async {
        final prefs = await SharedPreferences.getInstance();
        final set = (prefs.getStringList(_key) ?? []).toSet();
        for (final id in ids) {
          if (set.add(id)) await _recordEvent('c:$id', false);
        }
        final items = {
          for (final item in await getTmdbFavorites()) item.key: item,
        };
        for (final item in tmdb) {
          if (items.containsKey(item.key)) continue;
          items[item.key] = item;
          await _recordEvent('t:${item.key}', false, payload: item.toJson());
        }
        await prefs.setStringList(_key, set.toList());
        await prefs.setString(
          _tmdbKey,
          jsonEncode(items.values.map((v) => v.toJson()).toList()),
        );
        SyncHooks.settingsChanged();
      });

  Future<void> saveFavoriteIds(Iterable<String> ids) => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, ids.toList());
  });

  Future<List<TmdbItem>> getTmdbFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tmdbKey);
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map((e) => TmdbItem.tryParse(e))
        .whereType<TmdbItem>()
        .toList();
  }

  Future<List<TmdbItem>> toggleTmdbFavorite(TmdbItem item) =>
      _serialized(() async {
        final items = await getTmdbFavorites();
        final before = items.length;
        items.removeWhere((e) => e.key == item.key);
        if (items.length == before) items.insert(0, item);
        await _recordEvent(
          't:${item.key}',
          !items.any((v) => v.key == item.key),
          payload: item.toJson(),
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _tmdbKey,
          jsonEncode(items.map((e) => e.toJson()).toList()),
        );
        SyncHooks.settingsChanged();
        return items;
      });
}
