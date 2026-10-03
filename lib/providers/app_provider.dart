import 'package:flutter/foundation.dart';
import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/series_details.dart';
import '../models/tmdb_item.dart';
import '../services/catalog_builder.dart';
import '../services/playlist_refresh_service.dart';
import '../services/xtream_service.dart';
import '../services/favorites_service.dart';
import '../services/settings_service.dart';
import '../services/series_grouping.dart';

enum AuthMethod { none, xtream }

class AppProvider extends ChangeNotifier {
  final _xtreamService = XtreamService();
  final _favoritesService = FavoritesService();
  final _settingsService = SettingsService();
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

  List<Channel> channelsOf(ContentType type) =>
      _allChannels.where((c) => c.type == type).toList();

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
      return SeriesGrouping.catalog(channelsOf(type));
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
    notifyListeners();
    await _settingsService.setHiddenCategories(_hiddenCategories);
  }

  /// Catalog grouped by category, preserving the playlist's category order,
  /// with duplicates removed and hidden categories excluded.
  List<CatalogGroup> groupedCatalog(ContentType type) =>
      CatalogBuilder.groupsOf(
        _visibleChannels(type),
        categoryOrderOf(type)
            .where((g) => !hiddenCategoriesOf(type).contains(g))
            .toList(),
      );

  /// Recently added items of a type, in the playlist's own order (the
  /// provider lists newest entries last, so newest-first means reversed).
  List<CatalogEntry> recentEntries(ContentType type, {int limit = 60}) {
    final channels = _visibleChannels(type).reversed;
    final entries = <CatalogEntry>[];
    final seen = <String>{};
    for (final c in channels) {
      final base = CatalogBuilder.normalize(
          CatalogBuilder.stripQuality(c.displaySeriesName));
      if (base.isEmpty || seen.contains(base)) continue;
      seen.add(base);
      entries.add(CatalogEntry(
          primary: c, variants: type == ContentType.live ? [c] : variantsFor(c)));
      if (entries.length >= limit) break;
    }
    return entries;
  }

  /// All playlist copies of a title (other qualities/categories). Used by the
  /// detail screen to offer quality selection before playback.
  List<Channel> variantsFor(Channel channel) {
    final base = CatalogBuilder.normalize(
        CatalogBuilder.stripQuality(channel.displaySeriesName));
    if (base.isEmpty) return [channel];
    final sameType = channelsOf(channel.type);
    return [
      for (final c in sameType)
        if (CatalogBuilder.normalize(
                CatalogBuilder.stripQuality(c.displaySeriesName)) ==
            base)
          c,
    ];
  }

  List<Channel> get favorites =>
      _allChannels.where((c) => _favoriteIds.contains(c.id)).toList();

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
      if (loose == null && target.length >= 4 && name.contains(target)) {
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
    return loose;
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
    _tmdbFavorites = await _favoritesService.toggleTmdbFavorite(item);
    notifyListeners();
  }

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
    for (final id in ids) {
      if (!_favoriteIds.contains(id)) {
        // Persist through the service so both storage layers stay aligned.
        final channel = channelById(id);
        if (channel != null) await _favoritesService.toggleFavorite(channel);
      }
    }
    for (final item in tmdb) {
      if (!_tmdbFavorites.any((e) => e.key == item.key)) {
        await _favoritesService.toggleTmdbFavorite(item);
      }
    }
    _favoriteIds = await _favoritesService.getFavoriteIds();
    _tmdbFavorites = await _favoritesService.getTmdbFavorites();
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
    _tmdbFavorites = await _favoritesService.getTmdbFavorites();
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

  Future<void> toggleFavorite(Channel channel) async {
    await _favoritesService.toggleFavorite(channel);
    _favoriteIds = await _favoritesService.getFavoriteIds();
    notifyListeners();
  }
}
