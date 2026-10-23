import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/history_entry.dart';
import '../models/catalog_load_state.dart';
import '../models/series_details.dart';
import '../models/tmdb_item.dart';
import '../services/catalog_builder.dart';
import '../services/catalog_index_builder.dart';
import '../services/playlist_refresh_service.dart';
import '../services/playback_work_policy.dart';
import '../services/foreground_policy.dart';
import '../services/xtream_service.dart';
import '../services/cloud_favorites_service.dart';
import '../services/favorites_service.dart';
import '../services/sync_hooks.dart';
import '../services/settings_service.dart';
import '../services/sync_service.dart';
import '../services/series_grouping.dart';
import '../services/kids_content_service.dart';
import '../services/catalog_cache_service.dart';
import '../services/catalog_publication.dart';
import '../services/frame_telemetry_service.dart';
import '../models/custom_category.dart';

enum AuthMethod { none, xtream }

class AppProvider extends ChangeNotifier {
  AppProvider({XtreamService? xtreamService, CatalogCacheService? catalogCache})
    : _xtreamService = xtreamService ?? XtreamService(),
      _catalogCache = catalogCache ?? CatalogCacheService() {
    PlaybackWorkPolicy.instance.addListener(_onPlaybackWorkChanged);
  }

  void _onPlaybackWorkChanged() {
    final active = PlaybackWorkPolicy.instance.hasPlayback || _mainPlayerActive;
    if (!ForegroundPolicy.instance.active) {
      _deferredRefreshTimer?.cancel();
      _pendingTimer?.cancel();
    } else if (!active && _refreshDeferred) {
      _deferredRefreshTimer?.cancel();
      _deferredRefreshTimer = Timer(const Duration(seconds: 20), () {
        if (!ForegroundPolicy.instance.active ||
            _playbackActive ||
            !_refreshDeferred)
          return;
        _refreshDeferred = false;
        unawaited(refreshPlaylist());
      });
    }
    if (active != _playbackActive) _setEffectivePlaybackActive(active);
    if (!active &&
        ForegroundPolicy.instance.active &&
        _pendingSections.isNotEmpty &&
        !(_pendingTimer?.isActive ?? false)) {
      _pendingTimer = Timer(
        const Duration(milliseconds: 900),
        _applyPendingSections,
      );
    }
  }

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
  Map<String, Channel>? _seriesFolderIndex;
  Set<String> _favoriteIds = {};
  List<TmdbItem> _tmdbFavorites = [];
  Map<String, List<String>> _hiddenCategories = {};
  Map<String, List<String>> _categoryOrder = {};
  List<CustomCategory> _customCategories = [];
  bool _isLoading = false;
  bool _initialized = false;
  bool _startupLoading = false;
  bool _disposed = false;
  int _startupEpoch = 0;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

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
    _indexEpoch++;
    _matchCache.clear();
    _seriesFolderIndex = null;
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

  // ---- Playback guard ----------------------------------------------------
  bool _playbackActive = false;
  bool _mainPlayerActive = false;
  bool get playbackActive => _playbackActive;
  final Map<ContentType, List<Channel>> _pendingSections = {};
  Timer? _pendingTimer;
  bool _refreshDeferred = false;
  Timer? _deferredRefreshTimer;

  /// Called by the player: while a video plays, background playlist updates
  /// keep downloading but heavy catalog rebuilds wait until it closes.
  void setPlaybackActive(bool value) {
    _mainPlayerActive = value;
    _onPlaybackWorkChanged();
  }

  void _setEffectivePlaybackActive(bool value) {
    if (value == _playbackActive) return;
    _playbackActive = value;
    _pendingTimer?.cancel();
    _deferredRefreshTimer?.cancel();
    if (!value && _refreshDeferred) {
      // An automatic update was due during playback: run it only once the
      // player has been closed for a while, never while a video plays.
      _deferredRefreshTimer = Timer(const Duration(seconds: 20), () {
        if (!ForegroundPolicy.instance.active ||
            _playbackActive ||
            !_refreshDeferred)
          return;
        _refreshDeferred = false;
        refreshPlaylist();
      });
    }
    if (!value && _titleIndex == null && _allChannels.isNotEmpty) {
      // Index skipped while the video played: build it once it closes.
      Timer(const Duration(seconds: 2), _startCatalogIndex);
    }
    if (!value && _pendingSections.isNotEmpty) {
      // Let the exit animation finish first.
      _pendingTimer = Timer(
        const Duration(milliseconds: 900),
        _applyPendingSections,
      );
    }
  }

  bool _publishingPending = false;
  final Set<Completer<void>> _visibilityWaits = {};
  void _cancelVisibilityWaits() {
    for (final wait in _visibilityWaits.toList()) {
      if (!wait.isCompleted) wait.complete();
    }
  }

  void _applyPendingSections() {
    if (_publishingPending) return;
    _publishingPending = true;
    unawaited(
      _publishPendingSections().whenComplete(() => _publishingPending = false),
    );
  }

  Future<void> _publishPendingSections() async {
    final key = _currentKey;
    while (_pendingSections.isNotEmpty &&
        key == _currentKey &&
        !_disposed &&
        !_playbackActive &&
        ForegroundPolicy.instance.active) {
      final entry = _pendingSections.entries.first;
      final snapshot = _rawChannels;
      final kids = _kidsMode, adult = _showAdult;
      final evidence = _titleInfoVersion;
      bool valid() =>
          !_disposed &&
          key == _currentKey &&
          !_playbackActive &&
          ForegroundPolicy.instance.active &&
          identical(snapshot, _rawChannels) &&
          kids == _kidsMode &&
          adult == _showAdult &&
          evidence == _titleInfoVersion &&
          identical(_pendingSections[entry.key], entry.value);
      final merged = await replaceCatalogSection(
        current: snapshot,
        replacement: entry.value,
        type: entry.key,
        stillCurrent: valid,
      );
      if (merged == null) continue;
      final visible = await filterCatalogForPublication(
        channels: merged,
        allowed: (c) => kids ? isKidsContent(c) : (adult || !isAdult(c)),
        requestEvidence: kids ? _kids.request : null,
        stillCurrent: valid,
      );
      if (visible == null || !valid()) continue;
      _pendingSections.remove(entry.key);
      _setChannels(merged, visible: visible);
      notifyListeners();
    }
  }

  void _setChannels(List<Channel> channels, {List<Channel>? visible}) {
    _rawChannels = channels;
    // The background age check is heavy on big playlists: start it once the
    // sections settle and the first navigation is done, not at every publish.
    _warmUpTimer?.cancel();
    if (channels.isNotEmpty) {
      void warm() {
        if (_playbackActive ||
            _anyPending ||
            !ForegroundPolicy.instance.active) {
          _warmUpTimer = Timer(const Duration(seconds: 30), warm);
          return;
        }
        unawaited(_kids.warmUp(_rawChannels));
      }

      _warmUpTimer = Timer(const Duration(seconds: 20), warm);
    }
    _applyAdultFilter(visible: visible);
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
    if (_playbackActive || _anyPending || !ForegroundPolicy.instance.active) {
      // Never compete with video or section publication for the UI thread.
      _prewarmTimer = Timer(
        const Duration(seconds: 10),
        () => unawaited(_prewarm()),
      );
      return;
    }
    final snapshot = _allChannels;
    if (snapshot.isEmpty) return;
    final steps = <void Function()>[
      () => groupedCatalog(ContentType.movie),
      () => recentEntries(ContentType.movie),
      () => catalogOf(ContentType.series),
      () => groupedCatalog(ContentType.series),
      () => recentEntries(ContentType.series),
      _startCatalogIndex,
      () => allEntries(ContentType.movie),
      () => allEntries(ContentType.series),
    ];
    for (final step in steps) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!identical(snapshot, _allChannels) ||
          _playbackActive ||
          _anyPending ||
          !ForegroundPolicy.instance.active)
        return;
      step();
    }
  }

  /// Bumped when new TMDB genres arrive, so pages can cache what they derive
  /// from them (e.g. the genre bar) between two updates.
  int _titleInfoVersion = 0;
  int get titleInfoVersion => _titleInfoVersion;

  void _applyAdultFilter({List<Channel>? visible}) {
    if (_kidsMode && visible == null) _kids.request(_rawChannels);
    _allChannels =
        visible ??
        _rawChannels
            .where(
              (c) => _kidsMode ? isKidsContent(c) : (_showAdult || !isAdult(c)),
            )
            .toList(growable: false);
    _channelIndex = null;
    _seriesFolderIndex = null;
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
  /// with duplicates removed and hidden categories excluded. Personal
  /// categories come first; the user's saved order then wins over both.
  List<CatalogGroup> groupedCatalog(ContentType type) =>
      _groupedCache[type] ??= () {
        final base = CatalogBuilder.groupsOf(
          _visibleChannels(type),
          categoryOrderOf(type)
              .where((g) => !hiddenCategoriesOf(type).contains(g))
              .toList(),
        );
        final customs = customCategoriesOf(type);
        final byLabel = <String, CatalogGroup>{};
        if (customs.isNotEmpty) {
          final byId = <String, CatalogEntry>{
            for (final g in base)
              for (final e in g.entries) e.primary.id: e,
          };
          for (final c in customs) {
            byLabel[c.name] = CatalogGroup(
              label: c.name,
              entries: [
                for (final id in c.itemIds)
                  if (byId[id] case final entry?) entry,
              ],
            );
          }
        }
        for (final g in base) {
          byLabel.putIfAbsent(g.label, () => g);
        }
        return [
          for (final label in applyCategoryOrder(
            byLabel.keys.toList(),
            _categoryOrder[type.name] ?? const [],
          ))
            if (byLabel[label] case final group?)
              if (group.entries.isNotEmpty) group,
        ];
      }();

  // ---- Personal categories and category order (device-local) ----

  List<CustomCategory> get customCategories => _customCategories;

  List<CustomCategory> customCategoriesOf(ContentType type) => [
    for (final c in _customCategories)
      if (c.type == type) c,
  ];

  /// Every label shown for [type] (personal + visible playlist categories)
  /// in the order the catalog uses, including empty personal categories.
  List<String> orderedCategoryLabels(ContentType type) {
    final defaults = <String>[
      for (final c in customCategoriesOf(type)) c.name,
      for (final g in categoryOrderOf(type))
        if (!hiddenCategoriesOf(type).contains(g)) g,
    ];
    return applyCategoryOrder(
      defaults.toSet().toList(),
      _categoryOrder[type.name] ?? const [],
    );
  }

  void _categoriesChanged(ContentType type) {
    _groupedCache.remove(type);
    _allCache.remove(type);
    _recentCache.remove(type);
    notifyListeners();
  }

  Future<void> setCategoryOrder(ContentType type, List<String> order) async {
    _categoryOrder = {..._categoryOrder, type.name: order};
    _categoriesChanged(type);
    await _settingsService.setCategoryOrder(_categoryOrder);
  }

  Future<void> resetCategoryOrder(ContentType type) async {
    _categoryOrder = {..._categoryOrder}..remove(type.name);
    _categoriesChanged(type);
    await _settingsService.setCategoryOrder(_categoryOrder);
  }

  Future<void> _saveCustom(ContentType type) async {
    _categoriesChanged(type);
    await _settingsService.setCustomCategories(_customCategories);
  }

  /// Returns null on success or an Italian error for the user.
  Future<String?> createCustomCategory(ContentType type, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return 'Scrivi un nome';
    if (clean.length > 40) return 'Massimo 40 caratteri';
    final taken = {
      ...customCategoriesOf(type).map((c) => c.name.toLowerCase()),
      ...categoryOrderOf(type).map((g) => g.toLowerCase()),
    };
    if (taken.contains(clean.toLowerCase())) return 'Nome già usato';
    _customCategories = [
      ..._customCategories,
      CustomCategory(
        id: '${type.name}-${DateTime.now().microsecondsSinceEpoch}',
        name: clean,
        type: type,
      ),
    ];
    await _saveCustom(type);
    return null;
  }

  Future<String?> renameCustomCategory(String id, String name) async {
    final current = _customCategories.where((c) => c.id == id).firstOrNull;
    if (current == null) return 'Categoria non trovata';
    final clean = name.trim();
    if (clean.isEmpty) return 'Scrivi un nome';
    if (clean.length > 40) return 'Massimo 40 caratteri';
    final taken = {
      for (final c in customCategoriesOf(current.type))
        if (c.id != id) c.name.toLowerCase(),
      ...categoryOrderOf(current.type).map((g) => g.toLowerCase()),
    };
    if (taken.contains(clean.toLowerCase())) return 'Nome già usato';
    final order = _categoryOrder[current.type.name];
    if (order != null) {
      _categoryOrder = {
        ..._categoryOrder,
        current.type.name: [
          for (final l in order) l == current.name ? clean : l,
        ],
      };
      await _settingsService.setCategoryOrder(_categoryOrder);
    }
    _customCategories = [
      for (final c in _customCategories)
        c.id == id ? c.copyWith(name: clean) : c,
    ];
    await _saveCustom(current.type);
    return null;
  }

  Future<void> deleteCustomCategory(String id) async {
    final current = _customCategories.where((c) => c.id == id).firstOrNull;
    if (current == null) return;
    _customCategories = [
      for (final c in _customCategories)
        if (c.id != id) c,
    ];
    await _saveCustom(current.type);
  }

  bool isInCustomCategory(String categoryId, Channel item) => _customCategories
      .any((c) => c.id == categoryId && c.itemIds.contains(item.id));

  Future<void> toggleInCustomCategory(String categoryId, Channel item) async {
    final current = _customCategories
        .where((c) => c.id == categoryId)
        .firstOrNull;
    if (current == null) return;
    final ids = [...current.itemIds];
    if (!ids.remove(item.id)) ids.insert(0, item.id);
    _customCategories = [
      for (final c in _customCategories)
        c.id == categoryId ? c.copyWith(itemIds: ids) : c,
    ];
    await _saveCustom(current.type);
  }

  /// Titles of a personal category resolved against the current playlist.
  List<CatalogEntry> customCategoryEntries(CustomCategory category) {
    final byId = <String, CatalogEntry>{
      for (final e in allEntries(category.type)) e.primary.id: e,
    };
    return [
      for (final id in category.itemIds)
        if (byId[id] case final entry?) entry,
    ];
  }

  /// Recently added items of a type, in the playlist's own order (the
  /// provider lists newest entries last, so newest-first means reversed).
  /// "Ultimi Aggiunti": the 100 newest items by the provider's added date
  /// (playlist order as tie-breaker, newest entries come last there).
  List<CatalogEntry> recentEntries(ContentType type, {int limit = 100}) =>
      (_recentCache[type] ??= () {
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
        ].toList(growable: false);
      }()).take(limit).toList(growable: false);

  /// "Visti di recente": up to [limit] titles of [type] watched or started,
  /// newest first. Episodes count for their series.
  List<CatalogEntry> recentlyWatchedEntries(
    ContentType type,
    List<HistoryEntry> history, {
    int limit = 100,
  }) {
    final sorted = [...history]
      ..sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
    final seen = <String>{};
    final out = <CatalogEntry>[];
    for (final e in sorted) {
      if (out.length >= limit) break;
      if (e.type != type) continue;
      final isSeries = type == ContentType.series || type == ContentType.anime;
      final Channel? c = isSeries
          ? (e.seriesKey.isNotEmpty ? seriesFolderFor(e.seriesKey) : null) ??
                channelById(e.contentId)
          : channelById(e.contentId);
      if (c == null || (_kidsMode && !isKidsContent(c))) continue;
      if (!seen.add(c.id)) continue;
      out.add(CatalogEntry(primary: c, variants: [c]));
    }
    return out;
  }

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
  /// playlist in a background isolate so the Home never freezes at launch.
  Map<String, List<Channel>>? _titleIndex;
  final Map<String, Channel?> _matchCache = {};
  int _indexEpoch = 0;
  bool _indexBuilding = false;
  bool get catalogIndexReady => _titleIndex != null;

  /// Starts (once) the off-thread grouping + title normalization. Never
  /// during playback: the result is applied after the player closes.
  void _startCatalogIndex() {
    if (_indexBuilding || _titleIndex != null || _disposed) return;
    if (_playbackActive) return;
    final snapshot = _allChannels;
    if (snapshot.isEmpty) return;
    _indexBuilding = true;
    final epoch = ++_indexEpoch;
    final movies = channelsOf(ContentType.movie);
    final movieNames = [for (final c in movies) c.name];
    final seriesItems = _seriesCatalogCache.containsKey(ContentType.series)
        ? const <Channel>[]
        : channelsOf(ContentType.series);
    final animeItems = _seriesCatalogCache.containsKey(ContentType.anime)
        ? const <Channel>[]
        : channelsOf(ContentType.anime);
    final seriesReady = _seriesCatalogCache[ContentType.series];
    final animeReady = _seriesCatalogCache[ContentType.anime];
    // Series already grouped on this thread: only their names travel.
    final seriesNames = seriesReady == null
        ? null
        : [for (final c in seriesReady) c];
    final animeNames = animeReady == null
        ? null
        : [for (final c in animeReady) c];
    unawaited(() async {
      CatalogIndexData? data;
      try {
        data = await Isolate.run(
          () => buildCatalogIndex(
            movieNames,
            seriesNames ?? seriesItems,
            animeNames ?? animeItems,
            alreadyGrouped: (seriesNames != null, animeNames != null),
          ),
        );
      } catch (_) {
        data = null;
      }
      _indexBuilding = false;
      if (_disposed) return;
      if (_titleIndex != null) return; // built synchronously meanwhile
      if (epoch != _indexEpoch || !identical(snapshot, _allChannels)) {
        // Playlist changed meanwhile: index the current one instead.
        if (_titleIndex == null) _startCatalogIndex();
        return;
      }
      _applyCatalogIndex(data, movies);
    }());
  }

  void _applyCatalogIndex(CatalogIndexData? data, List<Channel> movies) {
    if (data == null) {
      // Isolate unavailable: fall back to the previous synchronous build.
      _titleIndex = _buildTitleIndexSync();
    } else {
      final series = _seriesCatalogCache[ContentType.series] ??=
          data.seriesCatalog;
      final anime = _seriesCatalogCache[ContentType.anime] ??=
          data.animeCatalog;
      final lists = [movies, series, anime];
      final sizes = [
        movies.length,
        data.seriesCatalog.length,
        data.animeCatalog.length,
      ];
      final index = <String, List<Channel>>{};
      data.titles.forEach((key, codes) {
        final out = <Channel>[];
        for (final code in codes) {
          final kind = CatalogIndexData.kindOf(code);
          final i = CatalogIndexData.indexOf(code);
          final list = lists[kind];
          if (list.length != sizes[kind] || i >= list.length) continue;
          out.add(list[i]);
        }
        if (out.isNotEmpty) index[key] = out;
      });
      _titleIndex = index;
    }
    _matchCache.clear();
    _seriesFolderIndex = null;
    notifyListeners();
  }

  Map<String, List<Channel>> _buildTitleIndexSync() {
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
  /// O(1) lookup: Home cards call this on every build. While the series
  /// catalog is still grouped in background it answers null (no freeze).
  Channel? seriesFolderFor(String seriesKey, {bool wait = true}) {
    final grouped =
        _seriesCatalogCache.containsKey(ContentType.series) &&
        _seriesCatalogCache.containsKey(ContentType.anime);
    if (!wait && !grouped && _titleIndex == null) {
      _startCatalogIndex();
      if (_indexBuilding) return null;
    }
    final index = _seriesFolderIndex ??= () {
      final m = <String, Channel>{};
      for (final type in [ContentType.series, ContentType.anime]) {
        for (final c in catalogOf(type)) {
          final k = c.seriesKey;
          if (k != null && k.isNotEmpty) m.putIfAbsent(k, () => c);
        }
      }
      for (final type in [ContentType.series, ContentType.anime]) {
        for (final c in catalogOf(type)) {
          m.putIfAbsent(c.id, () => c);
        }
      }
      return m;
    }();
    return index[seriesKey];
  }

  /// True when the TMDB title can actually be watched with the playlist.
  /// Non-blocking: false until the background index is ready.
  bool isAvailable(TmdbItem item) => findChannelFor(item, wait: false) != null;

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
  /// While the background index is still being built this answers null
  /// without caching, and the Home refreshes as soon as it is ready.
  /// [wait] false is for the Home: it never blocks the UI thread. User
  /// actions (opening a title, search) keep the exact synchronous answer.
  Channel? findChannelFor(TmdbItem item, {bool wait = true}) {
    if (_matchCache.containsKey(item.key)) return _matchCache[item.key];
    if (_titleIndex == null) {
      if (!wait) {
        _startCatalogIndex();
        return null;
      }
      _titleIndex = _buildTitleIndexSync();
      _indexEpoch++; // the pending background result is now redundant
    }
    final result = _findChannelFor(item);
    _matchCache[item.key] = result;
    return result;
  }

  Channel? _findChannelFor(TmdbItem item) {
    final index = _titleIndex!;
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

  static final _yearPattern = RegExp(r'\b(19|20)\d{2}\b');
  static String? _yearOf(String name) =>
      _yearPattern.firstMatch(name)?.group(0);

  /// Title key without language prefix, brackets, quality tags and year.
  static String _dedupeKey(Channel c) {
    final k = _titleKey(c.seriesName ?? c.name);
    return k.isEmpty ? c.id : '${c.type.name}:$k';
  }

  static String _titleKey(String raw) => catalogTitleKey(raw);

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

  bool isTmdbFavorite(TmdbItem item) =>
      _tmdbFavorites.any((e) => e.key == item.key);

  Future<void> toggleTmdbFavorite(TmdbItem item) async {
    _tmdbFavorites = await _favoritesService.toggleTmdbFavorite(item);
    notifyListeners();
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

  Future<void> applyEncryptedFavorites(Map<String, dynamic> snapshot) async {
    await _favoritesService.applyEncrypted(snapshot);
    _favoriteIds = await _favoritesService.getFavoriteIds();
    _tmdbFavorites = await _favoritesService.getTmdbFavorites();
    _favoritesCache = null;
    notifyListeners();
  }

  Future<void> importFavorites(Map<String, dynamic> data) async {
    final ids = (data['ids'] as List?)?.cast<String>() ?? const [];
    final tmdb =
        (data['tmdb'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(TmdbItem.tryParse)
            .whereType<TmdbItem>()
            .toList() ??
        const <TmdbItem>[];
    await _favoritesService.importFavorites(ids, tmdb);
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
    _categoryOrder = await _settingsService.getCategoryOrder();
    _customCategories = await _settingsService.getCustomCategories();
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
    // Never start a playlist update while a video is playing.
    if (_playbackActive || !ForegroundPolicy.instance.active) {
      _refreshDeferred = true;
      return;
    }
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
    _categoryOrder = await _settingsService.getCategoryOrder();
    _customCategories = await _settingsService.getCustomCategories();
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

    unawaited(_finishStartup(saved).catchError((Object _) {}));
  }

  Future<void> _finishStartup(Set<ContentType> saved) async {
    final epoch = ++_startupEpoch;
    final startupKey = _currentKey;
    _startupLoading = true;
    try {
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
      if (!_disposed && epoch == _startupEpoch && startupKey == _currentKey) {
        await _refreshService.schedule();
      }
    } finally {
      if (epoch == _startupEpoch) _startupLoading = false;
      notifyListeners();
    }
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
    if (!ForegroundPolicy.instance.active ||
        credentials == null ||
        catalogState(section).isPending)
      return;
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
    if (_playbackActive || !ForegroundPolicy.instance.active) return;
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

  /// Never true during playback, so the wait screen cannot cover a video.
  bool get isRefreshingAny =>
      _anyPending &&
      !_playbackActive &&
      (!_startupLoading || _rawChannels.isEmpty);

  Future<void> _enqueue(ContentType type, Map<String, String> credentials) {
    final run = _sectionQueue.then((_) => _loadSection(type, credentials));
    _sectionQueue = run.catchError((_) {});
    return run;
  }

  Future<void> _loadSection(
    ContentType type,
    Map<String, String> credentials,
  ) async {
    if (_disposed) return;
    if (_playbackActive) {
      _refreshDeferred = true;
      _catalogStates[type] = CatalogLoadState(
        phase: _hasSection(type)
            ? CatalogLoadPhase.cached
            : CatalogLoadPhase.idle,
        hasContent: _hasSection(type),
      );
      notifyListeners();
      return;
    }
    if (!ForegroundPolicy.instance.active) {
      final done = Completer<void>();
      _visibilityWaits.add(done);
      void resumed() {
        if (ForegroundPolicy.instance.active && !done.isCompleted)
          done.complete();
      }

      ForegroundPolicy.instance.addListener(resumed);
      try {
        resumed();
        await done.future;
      } finally {
        ForegroundPolicy.instance.removeListener(resumed);
        _visibilityWaits.remove(done);
      }
    }
    final server = credentials['server']!;
    final username = credentials['username']!;
    final password = credentials['password']!;
    final key = _cacheKey(credentials);
    if (_disposed || key != _currentKey) return; // account changed while queued
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
      if (_disposed || key != _currentKey) return;
      FrameTelemetryService.instance.mark(
        'catalogo: risposta pronta ${type.name}',
      );
      if (_playbackActive) {
        // A video is playing: swapping the catalog now re-filters and
        // rebuilds every page under the player, freezing the picture and
        // the remote. Keep the fresh section aside and apply it once the
        // player closes.
        _pendingSections[type] = channels;
      } else {
        // Publish each section atomically, yielding during merge/filter work.
        // Recheck settings/profile/account after every yield; never relax Kids.
        while (!_disposed &&
            key == _currentKey &&
            !_playbackActive &&
            ForegroundPolicy.instance.active) {
          final snapshot = _rawChannels;
          final kids = _kidsMode;
          final adult = _showAdult;
          final evidence = _titleInfoVersion;
          bool valid() =>
              !_disposed &&
              key == _currentKey &&
              identical(snapshot, _rawChannels) &&
              kids == _kidsMode &&
              adult == _showAdult &&
              evidence == _titleInfoVersion &&
              !_playbackActive &&
              ForegroundPolicy.instance.active;
          final merged = await replaceCatalogSection(
            current: snapshot,
            replacement: channels,
            type: type,
            stillCurrent: valid,
          );
          if (merged == null) continue;
          final visible = await filterCatalogForPublication(
            channels: merged,
            allowed: (c) => kids ? isKidsContent(c) : (adult || !isAdult(c)),
            requestEvidence: kids ? _kids.request : null,
            stillCurrent: valid,
          );
          if (visible == null || !valid()) continue;
          _pendingSections.remove(type);
          _setChannels(merged, visible: visible);
          FrameTelemetryService.instance.mark(
            'catalogo: pubblicato ${type.name}',
          );
          break;
        }
        if (_disposed || key != _currentKey) return;
        if (_playbackActive || !ForegroundPolicy.instance.active)
          _pendingSections[type] = channels;
      }
      _catalogStates[type] = CatalogLoadState(
        phase: CatalogLoadPhase.ready,
        hasContent: channels.isNotEmpty,
      );
      // Serialize cache workers with downloads instead of competing on TV CPU.
      await _catalogCache.writeSection(key, type, channels);
      FrameTelemetryService.instance.mark(
        'catalogo: copia salvata ${type.name}',
      );
    } catch (e) {
      if (_disposed || key != _currentKey) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      _loadFailures.add(message);
      if (!_hasSection(type)) {
        final cached = _cacheSnapshot ??= await _catalogCache.read(key);
        if (_disposed || key != _currentKey) return;
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
    _xtreamCredentials = null;
    _authMethod = AuthMethod.none;
    _activeLoadKey = null;
    _cancelVisibilityWaits();
    _startupEpoch++;
    _startupLoading = false;
    await _settingsService.clearCredentials();
    _refreshService.stop();
    // A new account must download its playlist completely the first time.
    unawaited(_refreshService.clearLastRun());
    _pendingSections.clear();
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

  /// Serialize local membership and its event before publishing UI changes.
  /// Network synchronization never blocks this local mutation.
  Future<void> toggleFavorite(Channel channel) async {
    _favoriteIds = await _favoritesService.toggleFavorite(channel);
    _favoritesCache = null;
    notifyListeners();
    unawaited(_mirrorChannelFavorite(channel).catchError((_) {}));
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelVisibilityWaits();
    _startupEpoch++;
    PlaybackWorkPolicy.instance.removeListener(_onPlaybackWorkChanged);
    _pendingTimer?.cancel();
    _deferredRefreshTimer?.cancel();
    _prewarmTimer?.cancel();
    _warmUpTimer?.cancel();
    _kidsRefresh?.cancel();
    _kids.dispose();
    _refreshService.dispose();
    super.dispose();
  }
}
