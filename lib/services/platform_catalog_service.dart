import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';
import '../models/streaming_platform.dart';
import '../models/tmdb_item.dart';
import 'tmdb_service.dart';

/// Titles each streaming platform offers in Italy (from TMDB), loaded on
/// demand when the user picks a platform in Film / Serie TV and kept on the
/// device for a day. Only public TMDB data is stored; playlist matching is
/// done locally and never synced.
class PlatformCatalogService extends ChangeNotifier {
  PlatformCatalogService._();
  static final instance = PlatformCatalogService._();

  static const _ttl = Duration(hours: 24);
  static const _prefix = 'platform_catalog_v1:';

  final Map<String, List<TmdbItem>> _items = {};
  final Map<String, Set<int>> _titleIds = {};
  final Map<String, Future<void>> _loading = {};
  int _version = 0;
  int get version => _version;

  static String _key(StreamingPlatform p, bool movies) =>
      '${p.name}:${movies ? 'movie' : 'tv'}';

  List<TmdbItem>? itemsOf(StreamingPlatform p, {required bool movies}) =>
      _items[_key(p, movies)];

  bool containsTitle(
    StreamingPlatform p, {
    required bool movies,
    required int id,
  }) => _titleIds[_key(p, movies)]?.contains(id) ?? false;

  bool isLoading(StreamingPlatform p, {required bool movies}) =>
      _loading.containsKey(_key(p, movies));

  Future<void> ensure(
    TmdbService tmdb,
    StreamingPlatform p, {
    required bool movies,
  }) {
    final key = _key(p, movies);
    if (_items.containsKey(key)) return Future.value();
    return _loading[key] ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('$_prefix$key');
        if (raw != null) {
          final m = jsonDecode(raw) as Map<String, dynamic>;
          final at = DateTime.tryParse('${m['at']}');
          if (at != null && DateTime.now().difference(at) < _ttl) {
            _items[key] = [
              for (final e in (m['items'] as List? ?? const []))
                if (e is Map)
                  if (TmdbItem.tryParse(e.cast<String, dynamic>())
                      case final item?)
                    item,
            ];
            _titleIds[key] = _items[key]?.map((i) => i.id).toSet() ?? <int>{};
            return;
          }
        }
        final items = await tmdb.platformCatalog(p, movies: movies);
        _items[key] = items;
        _titleIds[key] = items.map((i) => i.id).toSet();
        if (items.isNotEmpty) {
          await prefs.setString(
            '$_prefix$key',
            jsonEncode({
              'at': DateTime.now().toIso8601String(),
              'items': [for (final i in items) i.toJson()],
            }),
          );
        }
      } catch (_) {
        // Offline: the local name tags still filter the catalog.
      } finally {
        _loading.remove(key);
        _version++;
        notifyListeners();
      }
    }();
  }
}

/// Pure platform membership test shared by the catalog filter and tests:
/// a title belongs to a platform when TMDB lists it there ([tmdbIds] holds
/// the matched playlist ids) or the provider names it in the category/title.
bool belongsToPlatform(
  StreamingPlatform platform,
  Channel channel,
  Set<String> tmdbIds,
) =>
    tmdbIds.contains(channel.id) ||
    platform.tagMatches(channel.group) ||
    platform.tagMatches(channel.name);
