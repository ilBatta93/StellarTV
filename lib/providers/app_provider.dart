import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/catalog_load_state.dart';
import '../models/series_details.dart';
import '../models/tmdb_item.dart';
import '../services/catalog_builder.dart';
import '../services/playlist_refresh_service.dart';
import '../services/tmdb_service.dart';
import '../services/xtream_service.dart';
import '../services/cloud_favorites_service.dart';
import '../services/favorites_service.dart';
import '../services/settings_service.dart';
import '../services/sync_service.dart';
import '../services/series_grouping.dart';
import '../services/kids_content_service.dart';
import '../services/catalog_cache_service.dart';

enum AuthMethod { none, xtream }

class AppProvider extends ChangeNotifier {
  AppProvider({XtreamService? xtreamService, CatalogCacheService? catalogCache})
    : _xtreamService = xtreamService ?? XtreamService(),
      _catalogCache = catalogCache ?? CatalogCacheService();

  final XtreamService _xtreamService;
  final _favoritesService = FavoritesService();
  final _settingsService = SettingsService();
  final CatalogCacheService _catalogCache;
  CloudFavoritesService? _cloudFavorites;
  String? _syncCode;

  /// Builds the cloud client on first use. Returns null when Supabase has not
  /// been initialized (e.g. widget tests), so favorites simply stay local.
  CloudFavoritesService? get _cloud {
    try {
      return _cloudFavorites ??= CloudFavoritesService(
        Supabase.instance.client,
      );
    } catch (_) {
      return null;
    }
  }

  late final PlaylistRefreshService _refreshService = PlaylistRefreshService(
    refreshPlaylist,
  );

  List<Channel> _rawChannels = [];
  List<Channel> _allChannels = [];
  bool _showAdult = false;
  static const _showAdultKey = 'show_adult_content';
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
  List<TmdbItem> get tmdbFavorites =>
      _kidsMode ? _tmdbFavorites.where(isTmdbAllowed).toList() : _tmdbFavorites;
  bool get isLoading => _isLoading;
  final Map<ContentType, CatalogLoadState> _catalogStates = {};
  CatalogLoadState catalogState(ContentType type) =>
      _catalogStates[type == ContentType.anime ? ContentType.series : type] ??
      const CatalogLoadState();
  static const _playlistTypes = [
    ContentType.live,
    ContentType.movie,
    ContentType.series,
  ];
  bool _belongsToSection(Channel channel, ContentType type) =>
      channel.type == type ||
      (type == ContentType.series && channel.type == ContentType.anime);
  bool _hasSection(ContentType type) =>
      _rawChannels.any((channel) => _belongsToSection(channel, type));
  bool get isInitialized => _initialized;
  String? get error => _error;
  AuthMethod get authMethod => _authMethod;
  Map<String, String>? get xtreamCredentials => _xtreamCredentials;
  bool get isAuthenticated => _isAuthenticated;

  // Derived lists are cached: rebuilding them on every notify (e.g. when a
  // favorite changes) froze the UI with large playlists.
  final Map<ContentType, List<Channel>> _byType = {};
  final Map<ContentType, List<Channel>> _seriesCatalogCache = {};
  final Map<ContentType, List<CatalogGroup>> _groupedCache = {};
  final Map<ContentType, List<CatalogEntry>> _recentCache = {};
  List<Channel>? _favoritesCache;

  void _invalidateCaches() {
    _byType.clear();
    _seriesCatalogCache.clear();
    _groupedCache.clear();
    _allCache.clear();
    _recentCache.clear();
    _favoritesCache = null;
    _titleIndex = null;
    _matchCache.clear();
  }

  List<Channel> channelsOf(ContentType type) => _byType[type] ??= _allChannels
      .where((c) => c.type == type)
      .toList(growable: false);

  /// Channels of a type whose category is not hidden by the user.
  List<Channel> _visibleChannels(ContentType type) {
    final hidden = hiddenCategoriesOf(type).toSet();
    // Series tabs list whole series only: episodes indexed after opening a
    // series must never show up as separate titles.
    final base = (type == ContentType.series || type == ContentType.anime)
        ? catalogOf(type)
        : channelsOf(type);
    if (hidden.isEmpty) return base;
    return base.where((c) => !hidden.contains(c.group)).toList();
  }

  List<Channel> catalogOf(ContentType type) {
    if (type == ContentType.series || type == ContentType.anime) {
      return _seriesCatalogCache[type] ??= SeriesGrouping.catalog(
        channelsOf(type),
      );
    }
    return channelsOf(type);
  }

  List<String> languagesOf(ContentType type) =>
      catalogOf(type)
          .map((c) => c.language?.trim() ?? '')
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  List<String> countriesOf(ContentType type) =>
      catalogOf(type)
          .map((c) => c.country?.trim() ?? '')
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  Channel? channelById(String id) {
    final index = _channelIndex ??= {for (final c in _allChannels) c.id: c};
    final channel = index[id] ?? _episodeIndex[id];
    return channel != null && (!_kidsMode || isKidsContent(channel))
        ? channel
        : null;
  }

  /// Episodes loaded when a series page opens. Kept apart from the catalog:
  /// adding them to the full channel list re-filtered and re-grouped the whole
  /// playlist at every series opening (slow, and it made TV boxes run out of
  /// memory and close).
  final Map<String, Channel> _episodeIndex = {};
  static const _maxIndexedEpisodes = 4000;

  Timer? _warmUpTimer;

  void _setChannels(List<Channel> channels) {
    _rawChannels = channels;
    // The background age check is heavy on big playlists: start it once the
    // sections settle and the first navigation is done, not at every publish.
    _warmUpTimer?.cancel();
    if (channels.isNotEmpty) {
      _warmUpTimer = Timer(const Duration(seconds: 20), () {
        unawaited(_kids.warmUp(_rawChannels));
      });
    }
    _applyAdultFilter();
    _schedulePrewarm();
  }

  Timer? _prewarmTimer;

  /// Builds the Film/Serie TV lists in small steps while the user is still on
  /// the Home, so opening those tabs (above all right after launch) no longer
  /// waits for the whole playlist to be grouped.
  void _schedulePrewarm() {
    _prewarmTimer?.cancel();
    if (_rawChannels.isEmpty) return;
    _prewarmTimer = Timer(
      const Duration(seconds: 4),
      () => unawaited(_prewarm()),
    );
  }

  Future<void> _prewarm() async {
    final snapshot = _allChannels;
    if (snapshot.isEmpty) return;
    final steps = <void Function()>[
      () => groupedCatalog(ContentType.movie),
      () => recentEntries(ContentType.movie),
      () => catalogOf(ContentType.series),
      () => groupedCatalog(ContentType.series),
      () => recentEntries(ContentType.series),
      () => _titleIndex ??= _buildTitleIndex(),
      () => allEntries(ContentType.movie),
      () => allEntries(ContentType.series),
    ];
    for (final step in steps) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!identical(snapshot, _allChannels)) return;
      step();
    }
  }

  /// Bumped when new TMDB genres arrive, so pages can cache what they derive
  /// from them (e.g. the genre bar) between two updates.
  int _titleInfoVersion = 0;
  int get titleInfoVersion => _titleInfoVersion;

  void _applyAdultFilter() {
    if (_kidsMode) _kids.request(_rawChannels);
    _allChannels = _rawChannels
        .where(
          (c) => _kidsMode ? isKidsContent(c) : (_showAdult || !isAdult(c)),
        )
        .toList(growable: false);
    _channelIndex = null;
    _invalidateCaches();
  }

  /// Kids profile: only children's categories/channels are visible.
  bool _kidsMode = false;
  bool get kidsMode => _kidsMode;

  void setKidsMode(bool value) {
    if (value == _kidsMode) return;
    _kidsMode = value;
    if (value) {
      _kids.load().then((_) {
        if (!_kidsMode) return;
        _applyAdultFilter();
        notifyListeners();
      });
    }
    _applyAdultFilter();
    _schedulePrewarm();
    notifyListeners();
  }

  late final KidsContentService _kids = KidsContentService()
    ..onVerdicts = _onKidsVerdicts;
  Timer? _kidsRefresh;

  /// Throttled (not debounced): verdicts arrive in a continuous stream of
  /// small batches, and rebuilding every list after each one made the whole
  /// interface sluggish while the check was running.
  void _onKidsVerdicts() {
    if (_kidsRefresh?.isActive ?? false) return;
    _kidsRefresh = Timer(
      _kidsMode ? const Duration(seconds: 3) : const Duration(seconds: 30),
      () {
        _titleInfoVersion++;
        if (_kidsMode) _applyAdultFilter();
        notifyListeners();
      },
    );
  }

  /// One strict policy for all content types, including live channels.
  bool isKidsContent(Channel c) {
    if (isAdult(c)) return false;
    if (KidsContentService.bannedKeywords.hasMatch('${c.name} ${c.group}')) {
      return false;
    }
    return _kids.isKidsContent(c);
  }

  /// Adult content is hidden by default; the user can show it in Settings.
  bool get showAdult => _showAdult;

  Future<void> setShowAdult(bool value) async {
    if (value == _showAdult) return;
    _showAdult = value;
    _applyAdultFilter();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showAdultKey, value);
  }

  static final _adultPattern = RegExp(
    r'\bx{3,}\b|for\s*adults?|\badults?\b|\badulti\b|\b18\s*\+|\+\s*18\b|'
    r'\bporn|\bp0rn|\bhentai\b|\beroti[ck]|\bsexy?\b|\bhot\s*club\b|'
    r'playboy|brazzers|dorcel|hustler|penthouse|redlight|red\s*light|'
    r'private\s*(tv|spice)|\bspice\b|vivid|xxl\s*tv|blue\s*hustler|\bnsfw\b|milf',
    caseSensitive: false,
  );
  static final _adultExceptions = RegExp(
    r'adult\s*swim|young\s*adults?',
    caseSensitive: false,
  );

  /// True for pornographic items: "XXX" or "for adults" in the title or
  /// category, plus well known adult channel brands and keywords.
  static bool isAdult(Channel c) {
    bool test(String? s) {
      if (s == null || s.isEmpty) return false;
      final clean = s.replaceAll(_adultExceptions, ' ');
      return _adultPattern.hasMatch(clean);
    }

    return test(c.group) || test(c.name) || test(c.seriesName);
  }

  List<String> groupsOf(ContentType type) =>
      catalogOf(type).map((c) => c.group).toSet().toList()..sort();

  /// Category labels in the playlist's own order (not alphabetical).
  List<String> categoryOrderOf(ContentType type) => channelsOf(type)
      .where(
        (c) =>
            (type != ContentType.series && type != ContentType.anime) ||
            c.isSeriesFolder,
      )
      .map((c) => c.group)
      .toSet()
      .toList();

  /// Categories the user hid per type (key: content type name).
  Map<String, List<String>> get hiddenCategories => _hiddenCategories;

  List<String> hiddenCategoriesOf(ContentType type) =>
      _hiddenCategories[type.name] ?? const [];

  Future<void> setHiddenCategories(
    ContentType type,
    List<String> hidden,
  ) async {
    _hiddenCategories = {..._hiddenCategories, type.name: hidden};
    _groupedCache.remove(type);
    _allCache.remove(type);
    _recentCache.remove(type);
    notifyListeners();
    await _settingsService.setHiddenCategories(_hiddenCategories);
  }

  /// Catalog grouped by category, preserving the playlist's category order,
  /// with duplicates removed and hidden categories excluded.
  List<CatalogGroup> groupedCatalog(ContentType type) =>
      _groupedCache[type] ??= CatalogBuilder.groupsOf(
        _visibleChannels(type),
        categoryOrderOf(
          type,
        ).where((g) => !hiddenCategoriesOf(type).contains(g)).toList(),
      );

  /// Recently added items of a type, in the playlist's own order (the
  /// provider lists newest entries last, so newest-first means reversed).
  /// "Ultimi Aggiunti": the 50 newest items by the provider's added date
  /// (playlist order as tie-breaker, newest entries come last there).
  List<CatalogEntry> recentEntries(ContentType type, {int limit = 50}) =>
      _recentCache[type] ??= () {
        final items = _visibleChannels(type);
        final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])]
          ..sort((a, b) {
            final byDate = b.$2.addedAt.compareTo(a.$2.addedAt);
            return byDate != 0 ? byDate : b.$1.compareTo(a.$1);
          });
        // The same title is often listed in several categories: show it
        // once (normalized title, quality tags ignored).
        final seen = <String>{};
        return [
          for (final (_, c) in indexed)
            if (seen.add(_dedupeKey(c)))
              CatalogEntry(primary: c, variants: [c]),
        ].take(limit).toList(growable: false);
      }();

  /// Basic handling: every playlist item is played as it is, no merging of
  /// copies with different quality (that matching opened the wrong title).
  List<Channel> variantsFor(Channel channel) => [channel];

  List<Channel> get favorites =>
      _favoritesCache ??= [for (final id in _favoriteIds) ?channelById(id)];

  /// TMDB genre ids of a playlist movie/series (null while not checked yet).
  List<int>? genresOf(Channel c) => _kids.genresOf(c);

  /// Asks the background TMDB check for genres of exactly these titles (the
  /// catalog cards), so the genre bar fills for series folders too.
  void requestTitleInfo(Iterable<Channel> items) => _kids.request(items);

  /// "Tutti i Film" / "Tutte le Serie": every visible title once, A-Z.
  List<CatalogEntry> allEntries(ContentType type) => _allCache[type] ??= () {
    final seen = <String>{};
    final list =
        [
          for (final g in groupedCatalog(type))
            for (final e in g.entries)
              if (seen.add(_dedupeKey(e.primary))) e,
        ]..sort(
          (a, b) => a.primary.name.toLowerCase().compareTo(
            b.primary.name.toLowerCase(),
          ),
        );
    return list;
  }();
  final Map<ContentType, List<CatalogEntry>> _allCache = {};

  List<Channel> searchChannels(String query, {ContentType? type}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    if (type == ContentType.series || type == ContentType.anime) {
      // One pass over the playlist to find series whose episodes match,
      // instead of scanning every episode for every series (very slow).
      final episodeHits = <String>{};
      for (final e in _allChannels) {
        final key = e.seriesKey;
        if (key != null && e.name.toLowerCase().contains(q)) {
          episodeHits.add(key);
        }
      }
      return catalogOf(type!)
          .where(
            (c) =>
                c.name.toLowerCase().contains(q) ||
                c.group.toLowerCase().contains(q) ||
                episodeHits.contains(c.seriesKey),
          )
          .toList();
    }
    return _allChannels
        .where(
          (c) =>
              (type == null || c.type == type) &&
              !c.isSeriesFolder &&
              c.name.toLowerCase().contains(q),
        )
        .toList();
  }

  /// Normalized title -> playlist movies / series folders, built once per
  /// playlist so the Top lists can check availability instantly.
  Map<String, List<Channel>>? _titleIndex;
  final Map<String, Channel?> _matchCache = {};

  Map<String, List<Channel>> _buildTitleIndex() {
    final index = <String, List<Channel>>{};
    void add(String key, Channel c) {
      if (key.isEmpty) return;
      (index[key] ??= []).add(c);
    }

    for (final c in catalogOf(ContentType.movie)) {
      add(_titleKey(c.name), c);
    }
    for (final type in [ContentType.series, ContentType.anime]) {
      for (final c in catalogOf(type)) {
        add(_titleKey(c.name), c);
        if (c.seriesName != null) add(_titleKey(c.seriesName!), c);
      }
    }
    return index;
  }

  /// Series folder for an episode's series key.
  Channel? seriesFolderFor(String seriesKey) {
    for (final type in [ContentType.series, ContentType.anime]) {
      for (final c in catalogOf(type)) {
        if (c.seriesKey == seriesKey || c.id == seriesKey) return c;
      }
    }
    return null;
  }

  /// True when the TMDB title can actually be watched with the playlist.
  bool isAvailable(TmdbItem item) => findChannelFor(item) != null;

  /// External search/credits cannot bypass the verified playlist catalog.
  bool isTmdbAllowed(TmdbItem item) {
    if (!_kidsMode) return true;
    final channel = findChannelFor(item);
    return channel != null &&
        isKidsContent(channel) &&
        !KidsContentService.bannedKeywords.hasMatch(
          '${item.title} ${item.overview}',
        );
  }

  /// Finds the playlist title for a TMDB item. Movies need an exact title
  /// match and, when both sides have a year, the same year: this avoids
  /// opening a different film with the same name (remakes, sequels).
  Channel? findChannelFor(TmdbItem item) {
    if (_matchCache.containsKey(item.key)) return _matchCache[item.key];
    final result = _findChannelFor(item);
    _matchCache[item.key] = result;
    return result;
  }

  Channel? _findChannelFor(TmdbItem item) {
    final index = _titleIndex ??= _buildTitleIndex();
    final target = _titleKey(item.title);
    if (target.isEmpty) return null;
    final isMovie = item.contentType == ContentType.movie;
    final candidates = (index[target] ?? const <Channel>[])
        .where(
          (c) => isMovie
              ? c.type == ContentType.movie
              : c.type != ContentType.movie,
        )
        .toList();
    if (candidates.isEmpty) return null;
    final year = item.year;
    if (year.isNotEmpty) {
      Channel? sameYear;
      final noYear = <Channel>[];
      for (final c in candidates) {
        final y = _yearOf(c.name);
        if (y == year) {
          sameYear ??= c;
        } else if (y == null) {
          noYear.add(c);
        }
      }
      if (sameYear != null) return sameYear;
      // A different explicit year means a different title: skip it.
      return noYear.firstOrNull;
    }
    return candidates.first;
  }

  static String? _yearOf(String name) =>
      RegExp(r'\b(19|20)\d{2}\b').firstMatch(name)?.group(0);

  /// Title key without language prefix, brackets, quality tags and year.
  static String _dedupeKey(Channel c) {
    final k = _titleKey(c.seriesName ?? c.name);
    return k.isEmpty ? c.id : '${c.type.name}:$k';
  }

  static String _titleKey(String raw) =>
      _normalize(TmdbService.cleanTitle(raw));

  void indexEpisodes(List<Channel> episodes) {
    if (episodes.isEmpty) return;
    for (final e in episodes) {
      _episodeIndex.remove(e.id);
      _episodeIndex[e.id] = e;
    }
    // Oldest series first out: the map keeps insertion order.
    while (_episodeIndex.length > _maxIndexedEpisodes) {
      _episodeIndex.remove(_episodeIndex.keys.first);
    }
    _favoritesCache = null;
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
        return _safeSeriesDetails(details);
      } catch (_) {
        final local = SeriesGrouping.detailsFromEpisodes(series, _rawChannels);
        if (local.seasons.isNotEmpty) return _safeSeriesDetails(local);
        rethrow;
      }
    }
    return _safeSeriesDetails(
      SeriesGrouping.detailsFromEpisodes(series, _rawChannels),
    );
  }

  SeriesDetails _safeSeriesDetails(SeriesDetails details) {
    if (!_kidsMode) return details;
    if (!isKidsContent(details.series)) {
      return SeriesDetails(
        series: details.series,
        overview: '',
        seasons: const [],
      );
    }
    return SeriesDetails(
      series: details.series,
      overview: details.overview,
      seasons: [
        for (final season in details.seasons)
          SeriesSeason(
            number: season.number,
            name: season.name,
            episodes: season.episodes
                .where((e) => isKidsContent(e.channel))
                .toList(),
          ),
      ],
    );
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
    final tmdb =
        (data['tmdb'] as List?)
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
    _isLoading = true;
    _error = null;
    notifyListeners();
    _initialized = false;
    await init();
    await _refreshService.schedule();
  }

  /// Re-reads settings that may have been updated from another device.
  Future<void> reloadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _showAdult = prefs.getBool(_showAdultKey) ?? false;
    _hiddenCategories = await _settingsService.getHiddenCategories();
    final creds = await _settingsService.getXtreamCredentials();
    final credsChanged =
        creds != null &&
        (_xtreamCredentials == null ||
            creds['server'] != _xtreamCredentials!['server'] ||
            creds['username'] != _xtreamCredentials!['username'] ||
            creds['password'] != _xtreamCredentials!['password']);
    _applyAdultFilter();
    notifyListeners();
    if (credsChanged) {
      await reloadFromStorage();
    } else {
      await _refreshService.schedule();
    }
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
    _showAdult = prefs.getBool(_showAdultKey) ?? false;
    if (_syncCode != null) {
      // Network call: never hold the start-up (and the saved playlist) on it.
      unawaited(_restoreCloudFavorites(_syncCode!).catchError((_) {}));
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
    final saved = <ContentType>{};
    if (_xtreamCredentials case final credentials?) {
      final cached = await _catalogCache.read(_cacheKey(credentials));
      if (cached.isNotEmpty && _rawChannels.isEmpty) _setChannels(cached);
      for (final type in _playlistTypes) {
        if (_hasSection(type)) {
          saved.add(type);
          _catalogStates[type] = const CatalogLoadState(
            phase: CatalogLoadPhase.ready,
            hasContent: true,
          );
        }
      }
    }
    _initialized = true;
    notifyListeners();

    final credentials = _xtreamCredentials;
    if (_authMethod == AuthMethod.xtream && credentials != null) {
      final missing = [
        for (final type in _playlistTypes)
          if (!saved.contains(type)) type,
      ];
      if (missing.length == _playlistTypes.length) {
        // Nothing saved on this device yet: full first download.
        await loadFromXtream(
          server: credentials['server']!,
          username: credentials['username']!,
          password: credentials['password']!,
        );
      } else if (missing.isNotEmpty) {
        // Only the sections never saved are downloaded; the others open
        // instantly from the device copy.
        await _loadSections(missing, credentials);
      } else {
        _isLoading = false;
        _error = null;
        notifyListeners();
      }
    } else {
      _isLoading = false;
      notifyListeners();
    }
    // Automatic update only when the chosen interval has elapsed since the
    // last complete download.
    await _refreshService.schedule();
  }

  /// Downloads some sections only (missing from the device copy).
  Future<void> _loadSections(
    List<ContentType> types,
    Map<String, String> credentials,
  ) async {
    _activeLoadKey = _cacheKey(credentials);
    _isLoading = true;
    _error = null;
    _loadFailures.clear();
    for (final type in types) {
      _catalogStates[type] = CatalogLoadState(
        phase: CatalogLoadPhase.queued,
        hasContent: _hasSection(type),
      );
    }
    notifyListeners();
    try {
      for (final type in types) {
        await _enqueue(type, credentials);
      }
    } finally {
      _finishIfIdle();
    }
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

  // ---- Playlist sections -------------------------------------------------
  // Each section (Diretta, Film, Serie TV) downloads on its own, one at a
  // time through a shared queue (gentle on IPTV servers), publishes as soon
  // as it is ready and can be retried alone without touching the others.

  final Map<ContentType, ValueNotifier<CatalogProgress?>> _progress = {
    for (final type in _playlistTypes) type: ValueNotifier(null),
  };

  /// Live download progress of a section (bytes and titles received).
  ValueListenable<CatalogProgress?> catalogProgress(ContentType type) =>
      _progress[type == ContentType.anime ? ContentType.series : type]!;

  Future<void> _sectionQueue = Future.value();
  String? _activeLoadKey;
  List<Channel>? _cacheSnapshot;
  final List<String> _loadFailures = [];

  bool get _anyPending => _catalogStates.values.any((s) => s.isPending);

  String get _currentKey => _cacheKey(_xtreamCredentials ?? const {});

  /// Retries one section only; the other sections keep their content.
  Future<void> retrySection(ContentType type) async {
    final section = type == ContentType.anime ? ContentType.series : type;
    final credentials = _xtreamCredentials;
    if (credentials == null || catalogState(section).isPending) return;
    _catalogStates[section] = CatalogLoadState(
      phase: CatalogLoadPhase.queued,
      hasContent: _hasSection(section),
    );
    _isLoading = true;
    notifyListeners();
    await _enqueue(section, credentials);
    _finishIfIdle();
  }

  /// Manual "aggiorna tutto": reloads Diretta, Film and Serie TV one after
  /// the other (same queue as single retries, so memory stays bounded) and
  /// restarts the automatic-refresh timer from now.
  Future<void> refreshAllSections() async {
    if (_xtreamCredentials == null) return;
    await Future.wait([
      for (final t in const [
        ContentType.live,
        ContentType.movie,
        ContentType.series,
      ])
        retrySection(t),
    ]);
    if (_loadFailures.isEmpty) await _refreshService.markRun();
    await _refreshService.schedule();
  }

  bool get isRefreshingAny => _anyPending;

  Future<void> _enqueue(ContentType type, Map<String, String> credentials) {
    final run = _sectionQueue.then((_) => _loadSection(type, credentials));
    _sectionQueue = run.catchError((_) {});
    return run;
  }

  Future<void> _loadSection(
    ContentType type,
    Map<String, String> credentials,
  ) async {
    final server = credentials['server']!;
    final username = credentials['username']!;
    final password = credentials['password']!;
    final key = _cacheKey(credentials);
    if (key != _currentKey) return; // account changed while queued
    _catalogStates[type] = CatalogLoadState(
      phase: CatalogLoadPhase.loading,
      hasContent: _hasSection(type),
    );
    _progress[type]!.value = const CatalogProgress();
    notifyListeners();
    void onProgress(CatalogProgress p) => _progress[type]!.value = p;
    try {
      final channels = await switch (type) {
        ContentType.live => _xtreamService.getLiveChannels(
          server: server,
          username: username,
          password: password,
          onProgress: onProgress,
        ),
        ContentType.movie => _xtreamService.getVodChannels(
          server: server,
          username: username,
          password: password,
          onProgress: onProgress,
        ),
        _ => _xtreamService.getSeriesChannels(
          server: server,
          username: username,
          password: password,
          onProgress: onProgress,
        ),
      };
      if (key != _currentKey) return;
      // Publish each completed section immediately, not after all three.
      _setChannels([
        ..._rawChannels.where((c) => !_belongsToSection(c, type)),
        ...channels,
      ]);
      _catalogStates[type] = CatalogLoadState(
        phase: CatalogLoadPhase.ready,
        hasContent: channels.isNotEmpty,
      );
      unawaited(_catalogCache.writeSection(key, type, channels));
    } catch (e) {
      if (key != _currentKey) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      _loadFailures.add(message);
      if (!_hasSection(type)) {
        final cached = _cacheSnapshot ??= await _catalogCache.read(key);
        final fallback = cached.where((c) => _belongsToSection(c, type));
        if (fallback.isNotEmpty) _setChannels([..._rawChannels, ...fallback]);
      }
      final available = _hasSection(type);
      _catalogStates[type] = CatalogLoadState(
        phase: available ? CatalogLoadPhase.cached : CatalogLoadPhase.failed,
        hasContent: available,
        error: message,
      );
    } finally {
      _progress[type]!.value = null;
      notifyListeners();
    }
  }

  void _finishIfIdle() {
    if (_anyPending) return;
    _isLoading = false;
    _error = _rawChannels.isEmpty && _loadFailures.isNotEmpty
        ? _loadFailures.first
        : null;
    _loadFailures.clear();
    _cacheSnapshot = null;
    notifyListeners();
  }

  Future<void> loadFromXtream({
    required String server,
    required String username,
    required String password,
  }) async {
    final requestedKey = _cacheKey({'server': server, 'username': username});
    if (_anyPending && requestedKey == _activeLoadKey) return;
    _activeLoadKey = requestedKey;
    final current = _xtreamCredentials;
    final credentials =
        current != null &&
            _cacheKey(current) == requestedKey &&
            current['password'] == password
        ? current
        : {'server': server, 'username': username, 'password': password};
    _xtreamCredentials = credentials;
    _isLoading = true;
    _error = null;
    _loadFailures.clear();
    for (final type in _playlistTypes) {
      _catalogStates[type] = CatalogLoadState(
        phase: CatalogLoadPhase.queued,
        hasContent: _hasSection(type),
      );
    }
    notifyListeners();
    try {
      for (final type in _playlistTypes) {
        await _enqueue(type, credentials);
      }
      _isAuthenticated = true;
      final complete = _playlistTypes.every(
        (type) => _catalogStates[type]?.phase == CatalogLoadPhase.ready,
      );
      if (complete && requestedKey == _currentKey) {
        await _refreshService.markRun();
      }
    } finally {
      _finishIfIdle();
    }
  }

  String _cacheKey(Map<String, String> credentials) =>
      '${credentials['server'] ?? ''}|${credentials['username'] ?? ''}';

  Future<void> logout() async {
    await _settingsService.clearCredentials();
    _refreshService.stop();
    // A new account must download its playlist completely the first time.
    unawaited(_refreshService.clearLastRun());
    _setChannels([]);
    _catalogStates.clear();
    for (final p in _progress.values) {
      p.value = null;
    }
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

  @override
  void dispose() {
    _prewarmTimer?.cancel();
    _warmUpTimer?.cancel();
    _kidsRefresh?.cancel();
    super.dispose();
  }
}
