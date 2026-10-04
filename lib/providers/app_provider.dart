import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/series_details.dart';
import '../models/tmdb_item.dart';
import '../services/catalog_builder.dart';
import '../services/playlist_refresh_service.dart';
import '../services/xtream_service.dart';
import '../services/cloud_favorites_service.dart';
import '../services/favorites_service.dart';
import '../services/settings_service.dart';
import '../services/sync_service.dart';
import '../services/series_grouping.dart';

enum AuthMethod { none, xtream }

class AppProvider extends ChangeNotifier {
  final _xtreamService = XtreamService();
  final _favoritesService = FavoritesService();
  final _settingsService = SettingsService();
  CloudFavoritesService? _cloudFavorites;
  String? _syncCode;

  /// Builds the cloud client on first use. Returns null when Supabase has not
  /// been initialized (e.g. widget tests), so favorites simply stay local.
  CloudFavoritesService? get _cloud {
    try {
      return _cloudFavorites ??= CloudFavoritesService(Supabase.instance.client);
    } catch (_) {
      return null;
    }
  }
  late final PlaylistRefreshService _refreshService =
      PlaylistRefreshService(refreshPlaylist);

  List<Channel> _allChannels = [];
  Map<String, Channel>? _channelIndex;
  Set<String> _favoriteIds = {};
  List<TmdbItem> _tmdbFavorites = [];
  Map<String, List<String>> _hiddenCategories = {};
  bool _isLoading = false;
  bool _initialized = false;
  String? _error;
  AuthMethod _authMethod = AuthMethod.none;
  Map<String, String>? _xtreamCredentials;
  bool _isAuthenticated = false;

  List<Channel> get allChannels => _allChannels;
  Set<String> get favoriteIds => _favoriteIds;
  List<TmdbItem> get tmdbFavorites => _tmdbFavorites;
  bool get isLoading => _isLoading;
  bool get isInitialized => _initialized;
  String? get error => _error;
  AuthMethod get authMethod => _authMethod;
  Map<String, String>? get xtreamCredentials => _xtreamCredentials;
  bool get isAuthenticated => _isAuthenticated;

  // Derived lists are cached: rebuilding them on every notify (e.g. when a
  // favorite changes) froze the UI with large playlists.
  final Map<ContentType, List<Channel>> _byType = {};
  final Map<ContentType, List<Channel>> _catalogCache = {};
  final Map<ContentType, List<CatalogGroup>> _groupedCache = {};
  final Map<ContentType, List<CatalogEntry>> _recentCache = {};
  List<Channel>? _favoritesCache;

  void _invalidateCaches() {
    _byType.clear();
    _catalogCache.clear();
    _groupedCache.clear();
    _recentCache.clear();
    _favoritesCache = null;
  }

  List<Channel> channelsOf(ContentType type) => _byType[type] ??=
      _allChannels.where((c) => c.type == type).toList(growable: false);

  /// Channels of a type whose category is not hidden by the user.
  List<Channel> _visibleChannels(ContentType type) {
    final hidden = hiddenCategoriesOf(type).toSet();
    if (hidden.isEmpty) return channelsOf(type);
    return channelsOf(type)
        .where((c) => !hidden.contains(c.group))
        .toList();
  }

  List<Channel> catalogOf(ContentType type) {
    if (type == ContentType.series || type == ContentType.anime) {
      return _catalogCache[type] ??= SeriesGrouping.catalog(channelsOf(type));
    }
    return channelsOf(type);
  }

  List<String> languagesOf(ContentType type) => catalogOf(type)
      .map((c) => c.language?.trim() ?? '')
      .where((v) => v.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  List<String> countriesOf(ContentType type) => catalogOf(type)
      .map((c) => c.country?.trim() ?? '')
      .where((v) => v.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  Channel? channelById(String id) {
    final index = _channelIndex ??= {for (final c in _allChannels) c.id: c};
    return index[id];
  }

  void _setChannels(List<Channel> channels) {
    _allChannels = channels;
    _channelIndex = null;
    _invalidateCaches();
  }

  List<String> groupsOf(ContentType type) => catalogOf(type)
      .map((c) => c.group)
      .toSet()
      .toList()
    ..sort();

  /// Category labels in the playlist's own order (not alphabetical).
  List<String> categoryOrderOf(ContentType type) =>
      channelsOf(type).map((c) => c.group).toSet().toList();

  /// Categories the user hid per type (key: content type name).
  Map<String, List<String>> get hiddenCategories => _hiddenCategories;

  List<String> hiddenCategoriesOf(ContentType type) =>
      _hiddenCategories[type.name] ?? const [];

  Future<void> setHiddenCategories(ContentType type, List<String> hidden) async {
    _hiddenCategories = {
      ..._hiddenCategories,
      type.name: hidden,
    };
    _groupedCache.remove(type);
    _recentCache.remove(type);
    notifyListeners();
    await _settingsService.setHiddenCategories(_hiddenCategories);
  }

  /// Catalog grouped by category, preserving the playlist's category order,
  /// with duplicates removed and hidden categories excluded.
  List<CatalogGroup> groupedCatalog(ContentType type) =>
      _groupedCache[type] ??= CatalogBuilder.groupsOf(
        _visibleChannels(type),
        categoryOrderOf(type)
            .where((g) => !hiddenCategoriesOf(type).contains(g))
            .toList(),
      );

  /// Recently added items of a type, in the playlist's own order (the
  /// provider lists newest entries last, so newest-first means reversed).
  List<CatalogEntry> recentEntries(ContentType type, {int limit = 60}) =>
      _recentCache[type] ??= _visibleChannels(type)
          .reversed
          .take(limit)
          .map((c) => CatalogEntry(primary: c, variants: [c]))
          .toList(growable: false);

  /// Basic handling: every playlist item is played as it is, no merging of
  /// copies with different quality (that matching opened the wrong title).
  List<Channel> variantsFor(Channel channel) => [channel];

  List<Channel> get favorites => _favoritesCache ??= [
        for (final id in _favoriteIds)
          if (channelById(id) case final c?) c,
      ];

  List<Channel> searchChannels(String query, {ContentType? type}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    if (type == ContentType.series || type == ContentType.anime) {
      return catalogOf(type!)
          .where((c) =>
              c.name.toLowerCase().contains(q) ||
              (c.group.toLowerCase().contains(q)) ||
              _allChannels.any((e) =>
                  e.seriesKey == c.seriesKey &&
                  e.name.toLowerCase().contains(q)))
          .toList();
    }
    return _allChannels
        .where((c) =>
            (type == null || c.type == type) &&
            !c.isSeriesFolder &&
            c.name.toLowerCase().contains(q))
        .toList();
  }

  Channel? findChannelFor(TmdbItem item) {
    final target = _normalize(item.title);
    if (target.isEmpty) return null;
    Channel? loose;
    Channel? folder;
    for (final c in _allChannels) {
      if (c.type != item.contentType) continue;
      final name = _normalize(c.name);
      final seriesName = c.seriesName == null ? '' : _normalize(c.seriesName!);
      if (c.isSeriesFolder && (name == target || seriesName == target)) {
        return c;
      }
      if (name == target || seriesName == target) {
        if (c.isSeriesFolder) return c;
        folder ??= catalogOf(c.type)
            .where((s) => s.seriesKey == c.seriesKey)
            .firstOrNull;
        if (folder != null) return folder;
        return c;
      }
      if (loose == null &&
          item.contentType != ContentType.movie &&
          target.length >= 4 &&
          name.contains(target)) {
        loose = c;
      }
    }
    if ((item.contentType == ContentType.series ||
            item.contentType == ContentType.anime) &&
        loose != null) {
      return catalogOf(item.contentType)
              .where((s) => s.seriesKey == loose!.seriesKey || s.id == loose.seriesKey)
              .firstOrNull ??
          loose;
    }
    return item.contentType == ContentType.movie ? null : loose;
  }

  void indexEpisodes(List<Channel> episodes) {
    if (episodes.isEmpty) return;
    final ids = {for (final e in episodes) e.id};
    _setChannels([
      ..._allChannels.where((c) => !ids.contains(c.id)),
      ...episodes,
    ]);
  }

  Future<SeriesDetails> loadSeriesDetails(Channel series) async {
    if (_authMethod == AuthMethod.xtream &&
        _xtreamCredentials != null &&
        series.isSeriesFolder &&
        series.type == ContentType.series) {
      try {
        final details = await _xtreamService.getSeriesInfo(
          server: _xtreamCredentials!['server']!,
          username: _xtreamCredentials!['username']!,
          password: _xtreamCredentials!['password']!,
          series: series,
        );
        indexEpisodes(details.allEpisodes.map((e) => e.channel).toList());
        return details;
      } catch (_) {
        final local = SeriesGrouping.detailsFromEpisodes(series, _allChannels);
        if (local.seasons.isNotEmpty) return local;
        rethrow;
      }
    }
    return SeriesGrouping.detailsFromEpisodes(series, _allChannels);
  }

  static String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'^\s*[a-z]{2,3}\s*[:|\-]\s*'), '')
      .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9à-ÿ]+'), ' ')
      .trim();

  bool isTmdbFavorite(TmdbItem item) =>
      _tmdbFavorites.any((e) => e.key == item.key);

  Future<void> toggleTmdbFavorite(TmdbItem item) async {
    final before = _tmdbFavorites;
    _tmdbFavorites = isTmdbFavorite(item)
        ? before.where((e) => e.key != item.key).toList()
        : [item, ...before];
    notifyListeners();
    await _favoritesService.toggleTmdbFavorite(item);
    unawaited(_mirrorTmdbFavorite(item).catchError((_) {}));
  }

  /// Merges the cloud favorites for [code] into local storage. Newer local
  /// choices win: an item is only added locally, never removed, so a pull can
  /// not erase what the user just saved on this device.
  Future<void> _restoreCloudFavorites(String code) async {
    final rows = await _cloud?.load(code) ?? const [];
    if (rows.isEmpty) return;
    final channelIds = rows
        .where((r) => r['item_kind'] == 'channel')
        .map((r) => r['item_key']?.toString())
        .whereType<String>()
        .toList();
    final tmdbItems = rows
        .where((r) => r['item_kind'] == 'tmdb')
        .map((r) => r['payload'])
        .whereType<Map<String, dynamic>>()
        .map(TmdbItem.tryParse)
        .whereType<TmdbItem>()
        .toList();
    if (channelIds.isNotEmpty || tmdbItems.isNotEmpty) {
      await importFavorites({
        'ids': channelIds,
        'tmdb': tmdbItems.map((e) => e.toJson()).toList(),
      });
    }
  }

  Future<void> _mirrorChannelFavorite(Channel channel) async {
    final code = _syncCode;
    final cloud = _cloud;
    if (code == null || cloud == null) return;
    if (_favoriteIds.contains(channel.id)) {
      await cloud.addChannel(code, channel);
    } else {
      await cloud.remove(code, channel.id, 'channel');
    }
  }

  Future<void> _mirrorTmdbFavorite(TmdbItem item) async {
    final code = _syncCode;
    final cloud = _cloud;
    if (code == null || cloud == null) return;
    if (isTmdbFavorite(item)) {
      await cloud.addTmdb(code, item);
    } else {
      await cloud.remove(code, item.key, 'tmdb');
    }
  }

  /// Uploads every local favorite under [code]. Called when the user enables
  /// sync, so the cloud starts from the list already on the device.
  Future<void> pushAllFavorites(String code) async {
    _syncCode = code;
    await _cloud?.replaceAll(
      syncCode: code,
      channels: favorites,
      tmdbItems: _tmdbFavorites,
    );
  }

  /// Stops mirroring favorites to the cloud. Local favorites are kept.
  void clearCloudCode() => _syncCode = null;

  Map<String, dynamic> exportFavorites() => {
        'ids': _favoriteIds.toList(),
        'tmdb': _tmdbFavorites.map((e) => e.toJson()).toList(),
      };

  Future<void> importFavorites(Map<String, dynamic> data) async {
    final ids = (data['ids'] as List?)?.cast<String>() ?? const [];
    final tmdb = (data['tmdb'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(TmdbItem.tryParse)
            .whereType<TmdbItem>()
            .toList() ??
        const <TmdbItem>[];
    final newIds = <String>[..._favoriteIds];
    for (final id in ids) {
      if (!newIds.contains(id)) {
        // Persist through the service so both storage layers stay aligned.
        final channel = channelById(id);
        if (channel != null) await _favoritesService.toggleFavorite(channel);
        // Remember the id even when the channel is not in the playlist yet
        // (playlist still loading, or removed from the provider).
        newIds.add(id);
      }
    }
    await _favoritesService.saveFavoriteIds(newIds);
    for (final item in tmdb) {
      if (!_tmdbFavorites.any((e) => e.key == item.key)) {
        await _favoritesService.toggleTmdbFavorite(item);
      }
    }
    _favoriteIds = await _favoritesService.getFavoriteIds();
    _tmdbFavorites = await _favoritesService.getTmdbFavorites();
    _favoritesCache = null;
    notifyListeners();
  }

  /// Reloads credentials and playlist from local storage. Called after the
  /// account sync restores cloud data into local storage.
  Future<void> reloadFromStorage() async {
    _initialized = false;
    await init();
    await _refreshService.schedule();
  }

  Future<void> saveRefreshInterval(int minutes) async {
    await _refreshService.saveIntervalMinutes(minutes);
  }

  /// Reloads the playlist with the stored credentials or URL, without
  /// touching auth state. Used by the automatic refresh scheduler.
  Future<void> refreshPlaylist() async {
    if (_authMethod == AuthMethod.xtream && _xtreamCredentials != null) {
      await loadFromXtream(
        server: _xtreamCredentials!['server']!,
        username: _xtreamCredentials!['username']!,
        password: _xtreamCredentials!['password']!,
      );
    }
  }

  Future<void> init() async {
    _favoriteIds = await _favoritesService.getFavoriteIds();
    _favoritesCache = null;
    _tmdbFavorites = await _favoritesService.getTmdbFavorites();
    final prefs = await SharedPreferences.getInstance();
    _syncCode = prefs.getString(SyncService.codeKey);
    if (_syncCode != null) {
      await _restoreCloudFavorites(_syncCode!);
    }
    _hiddenCategories = await _settingsService.getHiddenCategories();
    final methodStr = await _settingsService.getAuthMethod();
    _authMethod = switch (methodStr) {
      'xtream' => AuthMethod.xtream,
      _ => AuthMethod.none,
    };
    _xtreamCredentials = await _settingsService.getXtreamCredentials();
    // Mark authenticated as soon as stored credentials exist, so the splash
    // routes to Home while the playlist is still loading in the background.
    _isAuthenticated =
        _authMethod == AuthMethod.xtream && _xtreamCredentials != null;
    _initialized = true;
    notifyListeners();

    if (_authMethod == AuthMethod.xtream && _xtreamCredentials != null) {
      await loadFromXtream(
        server: _xtreamCredentials!['server']!,
        username: _xtreamCredentials!['username']!,
        password: _xtreamCredentials!['password']!,
      );
    } else {
      _isLoading = false;
      notifyListeners();
    }
    await _refreshService.schedule();
  }

  Future<bool> loginWithXtream({
    required String server,
    required String username,
    required String password,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final ok = await _xtreamService.authenticate(
        server: server,
        username: username,
        password: password,
      );
      if (!ok) {
        _error = 'Autenticazione non riuscita. Controlla le credenziali.';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      await _settingsService.setAuthMethod('xtream');
      await _settingsService.setXtreamCredentials(
        server: server,
        username: username,
        password: password,
      );
      _authMethod = AuthMethod.xtream;
      _xtreamCredentials = {
        'server': server,
        'username': username,
        'password': password,
      };
      await loadFromXtream(
        server: server,
        username: username,
        password: password,
      );
      _isAuthenticated = true;
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> loadFromXtream({
    required String server,
    required String username,
    required String password,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final live = await _xtreamService.getLiveChannels(
        server: server,
        username: username,
        password: password,
      );
      final vod = await _xtreamService.getVodChannels(
        server: server,
        username: username,
        password: password,
      );
      final series = await _xtreamService.getSeriesChannels(
        server: server,
        username: username,
        password: password,
      );
      _setChannels([...live, ...vod, ...series]);
      _isAuthenticated = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _settingsService.clearCredentials();
    _setChannels([]);
    _authMethod = AuthMethod.none;
    _xtreamCredentials = null;
    _isAuthenticated = false;
    notifyListeners();
  }

  /// Updates the UI immediately, then saves locally and mirrors to the
  /// cloud in the background (the cloud call no longer blocks the tap).
  Future<void> toggleFavorite(Channel channel) async {
    final ids = {..._favoriteIds};
    if (!ids.remove(channel.id)) ids.add(channel.id);
    _favoriteIds = ids;
    _favoritesCache = null;
    notifyListeners();
    await _favoritesService.saveFavoriteIds(ids);
    unawaited(_mirrorChannelFavorite(channel).catchError((_) {}));
  }
}
