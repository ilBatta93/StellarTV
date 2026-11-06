import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';
import '../models/awards.dart';
import '../models/tmdb_item.dart';
import 'device_json_file.dart';
import 'foreground_http_client.dart';
import 'tmdb_service.dart';

/// Oscar and Emmy nominees from the site (static data, refreshed after each
/// ceremony), kept on the device for a day. Titles become TMDB items only
/// for the year and category on screen.
class AwardsService {
  AwardsService({http.Client? client, TmdbService? tmdb, DeviceJsonFile? file})
    : _client = client ?? ForegroundHttpClient(),
      _tmdb = tmdb ?? TmdbService(),
      _file = file ?? const DeviceJsonFile('awards_v1');

  static final instance = AwardsService();
  static const _ttl = Duration(days: 1);

  final http.Client _client;
  final TmdbService _tmdb;
  final DeviceJsonFile _file;
  AwardsCatalog? _catalog;
  Future<AwardsCatalog>? _loading;
  final _items = <String, Future<TmdbItem?>>{};

  /// Loaded and not empty: a TV row without titles would trap the remote.
  bool get hasCatalog => !(_catalog?.isEmpty ?? true);

  Future<AwardsCatalog> catalog() => _catalog != null
      ? Future.value(_catalog!)
      : (_loading ??= _load().whenComplete(() => _loading = null));

  Future<AwardsCatalog> _load() async {
    final saved = await _file.read();
    final savedAt = saved is Map
        ? DateTime.tryParse('${saved['savedAt']}')
        : null;
    final cached = saved is Map
        ? AwardsCatalog.fromJson(saved['data'])
        : AwardsCatalog.empty;
    if (!cached.isEmpty &&
        savedAt != null &&
        DateTime.now().difference(savedAt) < _ttl) {
      return _catalog = cached;
    }
    try {
      final res = await _client
          .get(Uri.parse('${SupabaseConfig.apiBase}/awards'))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        final fresh = AwardsCatalog.fromJson(body);
        if (!fresh.isEmpty) {
          await _file.write({
            'savedAt': DateTime.now().toIso8601String(),
            'data': body,
          });
          return _catalog = fresh;
        }
      }
    } catch (_) {
      // Offline: an older copy is better than an empty row.
    }
    if (!cached.isEmpty) return _catalog = cached;
    return AwardsCatalog.empty;
  }

  /// TMDB items of [nominees] in their order; titles TMDB cannot give back
  /// are left out. Requests go through the shared TMDB cache of the site.
  Future<List<TmdbItem>> items(List<AwardNominee> nominees) async {
    final found = await Future.wait([
      for (final n in nominees)
        _items.putIfAbsent(
          '${n.movie ? 'movie' : 'tv'}:${n.id}',
          () => _tmdb.itemById(n.id, movie: n.movie),
        ),
    ]);
    // A failed lookup may succeed later: do not keep it.
    for (var i = 0; i < nominees.length; i++) {
      if (found[i] == null) {
        _items.remove(
          '${nominees[i].movie ? 'movie' : 'tv'}:${nominees[i].id}',
        );
      }
    }
    return found.whereType<TmdbItem>().toList();
  }
}
