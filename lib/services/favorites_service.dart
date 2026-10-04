import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/channel.dart';
import '../models/tmdb_item.dart';

class FavoritesService {
  static const _key = 'favorite_channels';
  static const _tmdbKey = 'favorite_tmdb_items';

  Future<Set<String>> getFavoriteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    return list.toSet();
  }

  Future<void> toggleFavorite(Channel channel) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_key) ?? []).toSet();
    if (!set.remove(channel.id)) set.add(channel.id);
    await prefs.setStringList(_key, set.toList());
  }

  Future<void> saveFavoriteIds(Iterable<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, ids.toList());
  }

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

  Future<List<TmdbItem>> toggleTmdbFavorite(TmdbItem item) async {
    final items = await getTmdbFavorites();
    final before = items.length;
    items.removeWhere((e) => e.key == item.key);
    if (items.length == before) items.insert(0, item);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _tmdbKey, jsonEncode(items.map((e) => e.toJson()).toList()));
    return items;
  }
}
