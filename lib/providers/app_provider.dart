import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/history_entry.dart';
import '../models/catalog_load_state.dart';
import '../models/series_details.dart';
import '../models/tmdb_item.dart';
import '../services/catalog_rating_service.dart';
import '../services/catalog_builder.dart';
import '../services/catalog_preparation.dart';
import '../services/catalog_index_builder.dart';
import '../services/playlist_refresh_service.dart';
import '../services/playback_work_policy.dart';
import '../services/foreground_policy.dart';
import '../services/source_login_result.dart';
import '../services/xtream_service.dart';
import '../services/cloud_favorites_service.dart';
import '../services/favorites_service.dart';
import '../services/settings_service.dart';
import '../services/sync_service.dart';
import '../services/series_grouping.dart';
import '../services/kids_content_service.dart';
import '../services/catalog_cache_service.dart';
import '../services/catalog_shelf.dart';
import '../services/catalog_sort.dart' show CatalogSort;
import '../services/catalog_publication.dart';
import '../services/title_facet_index.dart';
import '../services/frame_telemetry_service.dart';
import '../services/device_type_service.dart';
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
            !_refreshDeferred) {
          return;
        }
        _refreshDeferred = false;
        unawaited(refreshPlaylist());
      });
    }
    if (active != _playbackActive) _setEffectivePlaybackActive(active);
    if (!active &&
        ForegroundPolicy.instance.active &&
        _hasDeferredCatalogWork &&
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

  CatalogShelf _shelf = CatalogShelf.empty();
  int _shelfEpoch = 0;
  bool _shelfReady = false;
  Uint8List _visibleMask = Uint8List(0);
  int _visibleCount = 0;
  final CatalogVisibility _visibility = CatalogVisibility();
  int get visibilityStamp => _visibility.stamp;
  bool _fullLoadActive = false;
  ShelfChannelList? _visibleView;
  final Map<ContentType, ShelfChannelList> _typedViews = {};
  bool _showAdult = false;
  static const _showAdultKey = 'show_adult_content';
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

  List<Channel> get allChannels =>
      _visibleView ?? ShelfChannelList(_shelf, const []);
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
  bool _hasSection(ContentType type) {
    if (type == ContentType.series) {
      return (_shelf.plan(ContentType.series)?.channels.isNotEmpty ?? false) ||
          (_shelf.plan(ContentType.anime)?.channels.isNotEmpty ?? false);
    }
    return _shelf.plan(type)?.channels.isNotEmpty ?? false;
  }

  bool get isInitialized => _initialized;
  String? get error => _error;
  AuthMethod get authMethod => _authMethod;
  Map<String, String>? get xtreamCredentials => _xtreamCredentials;
  bool get isAuthenticated => _isAuthenticated;

  // Derived lists are cached: rebuilding them on every notify (e.g. when a
  // favorite changes) froze the UI with large playlists.
  final Map<ContentType, List<Channel>> _seriesCatalogCache = {};
  final Map<ContentType, List<CatalogGroup>> _groupedCache = {};
  final Map<ContentType, List<CatalogEntry>> _recentCache = {};
  final Map<ContentType, Map<int, int>> _genreCountsCache = {};
  final Map<ContentType, int> _genreCountsVersions = {};
  final Map<ContentType, Future<void>> _genreCountJobs = {};
  List<Channel>? _favoritesCache;
  final Map<ContentType, _RecentWatchMemo> _watchedMemos = {};

  Map<String, List<String>> _titleCategories = const {};
  Timer? _titleCategoriesTimer;

  List<String> titleCategoriesOf(Channel channel) =>
      _titleCategories[catalogEntryKey(channel)] ??
      (channel.group.isEmpty ? const [] : [channel.group]);

  void _scheduleTitleCategories() {
    _titleCategories = _shelf.titleCategories;
  }

  int _preparationEpoch = 0;
  int _playlistRefreshRevision = 0;
  int get playlistRefreshRevision => _playlistRefreshRevision;
  final Map<ContentType, Future<void>> _preparing = {};

  bool get _largeCatalog => _shelf.length > 512;
  bool catalogPreparing(ContentType type) =>
      _largeCatalog && !_allCache.containsKey(type);

  String _settingsToken() => shelfSettingsToken(
    hidden: _hiddenCategories,
    custom: _customCategories,
    order: _categoryOrder,
  );

  Future<void> ensureCatalogPrepared(ContentType type) {
    final existing = _preparing[type];
    if (existing != null) return existing;
    if (_allCache.containsKey(type) || _disposed || _shelf.isEmpty) {
      return Future<void>.value();
    }
    final epoch = _shelfEpoch;
    late final Future<void> job;
    job = Future<void>.value()
        .then((_) async {
          if (_shelf.settingsToken != _settingsToken()) {
            final nextEpoch = ++_shelfEpoch;
            final next = await _shelf.retune(
              hidden: _hiddenCategories,
              custom: _customCategories,
              order: _categoryOrder,
              generation: nextEpoch,
            );
            if (_disposed || nextEpoch != _shelfEpoch) {
              if (!identical(next, _shelf)) next.close();
              return;
            }
            _swap(next, bumpWarmup: false);
          }
          if (_disposed ||
              epoch != _shelfEpoch && _allCache.containsKey(type)) {
            return;
          }
          if (!_allCache.containsKey(type)) _publishShelf(notify: false);
          notifyListeners();
        })
        .whenComplete(() {
          if (identical(_preparing[type], job)) _preparing.remove(type);
        });
    _preparing[type] = job;
    return job;
  }

  void _invalidateCaches() {
    _preparationEpoch++;
    _titleCategories = const {};
    _scheduleTitleCategories();
    _preparing.clear();
    _seriesCatalogCache.clear();
    _groupedCache.clear();
    _allCache.clear();
    _recentCache.clear();
    _genreCountsCache.clear();
    _genreCountsVersions.clear();
    _genreCountJobs.clear();
    _favoritesCache = null;
    _matchCache.clear();
    _watchedMemos.clear();
  }

  List<Channel> channelsOf(ContentType type) =>
      _typedViews[type] ?? ShelfChannelList(_shelf, const []);

  String idAt(int slot) => _shelf.idAt(slot);

  String groupAt(int slot) => _shelf.groupAt(slot);

  /// Shelf [slots] in [order], read off the UI isolate.
  Future<List<int>> sortSlots(List<int> slots, CatalogSort order) =>
      _shelf.sortSlots(slots, order);

  /// Name flags of every [type] title, read off the UI isolate. Keyed by
  /// slot, so callers drop the result when [catalogIndexRevision] changes.
  Future<Map<int, int>> nameFlagsOf(
    ContentType type,
    int Function(String name) flags,
  ) {
    final plan = _shelf.plan(type);
    if (plan == null) return Future.value(const {});
    final slots = <int>{
      ...plan.alphabetical,
      ...plan.recent,
      for (final group in plan.groupSlots) ...group,
    };
    return _shelf.nameFlags(slots.toList(growable: false), flags);
  }

  List<int>? genresForSlot(int slot) =>
      _kids.genresForKey(_shelf.facetKeyAt(slot));

  ShelfChannelList bindChannels(List<int> slots) =>
      ShelfChannelList(_shelf, slots);

  List<Channel> catalogOf(ContentType type) {
    if (type == ContentType.series || type == ContentType.anime) {
      final ready = _seriesCatalogCache[type];
      if (ready != null) return ready;
      unawaited(ensureCatalogPrepared(type));
      return const [];
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
    final channel = _episodeIndex[id] ?? _shelf.readId(id);
    if (channel == null) return null;
    if (_kidsMode && !isKidsContent(channel)) return null;
    if (!_kidsMode && !_showAdult && catalogChannelIsAdult(channel)) {
      return null;
    }
    return channel;
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

  /// True while a session is open or the app is not visible. Catalog files
  /// stay in memory until this is false; nothing is encoded on the UI isolate.
  bool get _catalogDiskBlocked =>
      _playbackActive || PlaybackWorkPolicy.instance.blocksCatalogWrite;
  final Map<ContentType, List<Channel>> _pendingSections = {};
  final Map<ContentType, List<Channel>> _pendingCatalogWrites = {};
  bool get _hasDeferredCatalogWork =>
      _pendingSections.isNotEmpty || _pendingCatalogWrites.isNotEmpty;
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
            !_refreshDeferred) {
          return;
        }
        _refreshDeferred = false;
        refreshPlaylist();
      });
    }
    if (!value && _visibleCount > 0 && !_shelfReady) {
      // Index skipped while the video played: build it once it closes.
      Timer(const Duration(seconds: 2), _startCatalogIndex);
    }
    if (!value && _hasDeferredCatalogWork) {
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
      final epoch = _shelfEpoch;
      final kids = _kidsMode;
      final adult = _showAdult;
      final evidence = _titleInfoVersion;
      bool valid() =>
          !_disposed &&
          key == _currentKey &&
          !_playbackActive &&
          ForegroundPolicy.instance.active &&
          epoch == _shelfEpoch &&
          kids == _kidsMode &&
          adult == _showAdult &&
          evidence == _titleInfoVersion &&
          identical(_pendingSections[entry.key], entry.value);
      if (!valid()) {
        _pendingSections.remove(entry.key);
        continue;
      }
      _pendingSections.remove(entry.key);
      await _publishResolved(entry.key, entry.value, key);
      notifyListeners();
    }
    await _flushDeferredCatalogCopies();
  }

  /// Encodes deferred sections only while the player is closed and the app
  /// is visible. Runs on the same queue as downloads so the two never overlap.
  /// Must not be called from inside that queue: waiting for it would deadlock.
  Future<void> _flushDeferredCatalogCopies() async {
    final key = _currentKey;
    if (_disposed ||
        _catalogDiskBlocked ||
        _pendingCatalogWrites.isEmpty ||
        key != _currentKey) {
      return;
    }
    final run = _sectionQueue.then((_) async {
      final pending = List<MapEntry<ContentType, List<Channel>>>.of(
        _pendingCatalogWrites.entries,
      );
      for (final entry in pending) {
        if (_disposed || key != _currentKey || _catalogDiskBlocked) return;
        if (!identical(_pendingCatalogWrites[entry.key], entry.value)) continue;
        await _persistSectionCopy(key, entry.key, entry.value);
      }
    });
    _sectionQueue = run.catchError((_) {});
    await run;
  }

  /// Keeps [channels] in memory until a complete file replaces the previous
  /// copy. A refused or interrupted write does not emit the saved marker.
  Future<bool> _persistSectionCopy(
    String key,
    ContentType type,
    List<Channel> channels,
  ) async {
    _pendingCatalogWrites[type] = channels;
    if (_disposed || key != _currentKey || _catalogDiskBlocked) return false;
    final saved = await _catalogCache.writeSection(
      key,
      type,
      channels,
      stillAllowed: () =>
          !_disposed && key == _currentKey && !_catalogDiskBlocked,
    );
    if (_disposed || key != _currentKey) return false;
    if (saved && identical(_pendingCatalogWrites[type], channels)) {
      _pendingCatalogWrites.remove(type);
      if (!_catalogDiskBlocked) {
        FrameTelemetryService.instance.mark(
          'catalogo: copia salvata ${type.name}',
        );
      }
    }
    return saved;
  }

  Future<void> _publishResolved(
    ContentType type,
    List<Channel> incoming,
    String key,
  ) async {
    if (await _catalogCache.hasSectionFile(key)) {
      await _installFromFiles(key, changed: type);
      return;
    }
    final epoch = _shelfEpoch;
    bool valid() =>
        !_disposed &&
        key == _currentKey &&
        epoch == _shelfEpoch &&
        !_playbackActive;
    final merged = await replaceCatalogSection(
      current: _shelf.materialize(),
      replacement: incoming,
      type: type,
      stillCurrent: valid,
    );
    if (merged == null || !valid()) return;
    await _installChannels(merged);
  }

  Future<void> _installFromFiles(String key, {ContentType? changed}) async {
    final epoch = ++_shelfEpoch;
    final paths = await _catalogCache.sectionPaths(key);
    final present = [
      for (final path in paths)
        if (File(path).existsSync()) path,
    ];
    if (_disposed || epoch != _shelfEpoch) return;
    if (present.isEmpty) {
      _swap(CatalogShelf.empty());
      return;
    }
    final token = _settingsToken();
    final reusable = !_shelf.isEmpty && _shelf.settingsToken == token;
    if (reusable) {
      final known = _shelf.sectionPaths.toSet();
      final targets = <String>[];
      if (changed != null) {
        final index = CatalogCacheService.sections.indexOf(changed);
        if (index >= 0 &&
            index < paths.length &&
            File(paths[index]).existsSync()) {
          targets.add(paths[index]);
        }
      }
      if (targets.isEmpty) {
        for (final path in present) {
          if (!known.contains(path)) targets.add(path);
        }
      }
      for (final path in targets) {
        await _openSavedSection(_shelf, path);
        if (_disposed || epoch != _shelfEpoch) return;
      }
      if (_disposed || epoch != _shelfEpoch) return;
      _swap(_shelf);
      return;
    }
    final shelf = CatalogShelf.empty();
    for (final path in present) {
      await _openSavedSection(shelf, path);
      if (_disposed || epoch != _shelfEpoch) {
        shelf.close();
        return;
      }
    }
    _swap(shelf);
  }

  Future<void> _openSavedSection(CatalogShelf shelf, String path) async {
    final adopted = await shelf.adoptIndex(path, token: _settingsToken());
    if (adopted) return;
    await shelf.appendSection(
      path,
      hidden: _hiddenCategories,
      custom: _customCategories,
      order: _categoryOrder,
    );
  }

  Future<void> _installChannels(List<Channel> channels) async {
    final epoch = ++_shelfEpoch;
    final shelf = channels.isEmpty
        ? CatalogShelf.empty()
        : await CatalogShelf.fromChannels(
            channels,
            hidden: _hiddenCategories,
            custom: _customCategories,
            order: _categoryOrder,
            generation: epoch,
          );
    if (_disposed || epoch != _shelfEpoch) {
      shelf.close();
      return;
    }
    _swap(shelf);
  }

  void _swap(CatalogShelf shelf, {bool bumpWarmup = true}) {
    final previous = _shelf;
    _shelf = shelf;
    _shelfReady = true;
    _invalidateCaches();
    _rebuildMask();
    _publishShelf(notify: false);
    if (!identical(previous, shelf)) previous.close();
    if (bumpWarmup) _schedulePrewarm();
    notifyListeners();
  }

  void _rebuildMask() {
    final clock = Stopwatch()..start();
    final count = _shelf.length;
    final mask = Uint8List(count);
    var visible = 0;
    if (_kidsMode) {
      for (var slot = 0; slot < count; slot++) {
        final show = _kids.allowsIndexed(
          adult: _shelf.isAdultSlot(slot),
          banned: _shelf.isBannedSlot(slot),
          category: _shelf.groupAt(slot),
          key: _shelf.facetKeyAt(slot),
        );
        _shelf.setKidsFlag(slot, show);
        if (show) {
          mask[slot] = 1;
          visible++;
        }
      }
    } else {
      for (var slot = 0; slot < count; slot++) {
        if (_showAdult || !_shelf.isAdultSlot(slot)) {
          mask[slot] = 1;
          visible++;
        }
      }
    }
    _visibleMask = mask;
    _visibleCount = visible;
    _visibility.setMask(mask);
    FrameTelemetryService.instance.recordWork('catalogo.maschera', clock);
  }

  CatalogEntry _slotEntry(int slot) => CatalogEntry.slot(slot, _shelf);

  void _publishShelf({bool notify = true}) {
    final clock = Stopwatch()..start();
    _typedViews.clear();
    _seriesCatalogCache.clear();
    for (final type in ContentType.values) {
      final plan = _shelf.plan(type);
      if (plan == null) continue;
      _typedViews[type] = ShelfChannelList(
        _shelf,
        plan.channels,
        visibility: _visibility,
      );
      if (type == ContentType.series || type == ContentType.anime) {
        _seriesCatalogCache[type] = ShelfChannelList(
          _shelf,
          plan.catalog,
          visibility: _visibility,
        );
      }
      final groups = <CatalogGroup>[];
      for (var i = 0; i < plan.labels.length; i++) {
        groups.add(
          CatalogGroup(
            label: plan.labels[i],
            entries: SlotEntryList(
              _shelf,
              plan.groupSlots[i],
              visibility: _visibility,
            ),
          ),
        );
      }
      _groupedCache[type] = groups;
      _recentCache[type] = SlotEntryList(
        _shelf,
        plan.recent,
        visibility: _visibility,
      );
      _allCache[type] = SlotEntryList(
        _shelf,
        plan.alphabetical,
        visibility: _visibility,
      );
      unawaited(_warmFacetNames(type, plan.alphabetical));
      unawaited(_ensureGenreCounts(type));
    }
    _visibleView = ShelfChannelList(_shelf, [
      for (var slot = 0; slot < _shelf.length; slot++) slot,
    ], visibility: _visibility);
    _titleCategories = _shelf.titleCategories;
    FrameTelemetryService.instance.recordWork('catalogo.pubblica', clock);
    if (notify) notifyListeners();
  }

  Future<void> _warmFacetNames(ContentType type, List<int> slots) async {
    if (type != ContentType.movie &&
        type != ContentType.series &&
        type != ContentType.anime) {
      return;
    }
    final epoch = _shelfEpoch;
    try {
      await _shelf.warmNames(type, (ids, names) {
        if (_disposed || epoch != _shelfEpoch) return;
        unawaited(TitleFacetIndex.instance.rank(type, ids, names));
        _kids.requestIndexed(_shelf.kidsIndexPairs(ids, names));
        unawaited(CatalogRatingService.instance.warmTitles(type, ids, names));
      });
    } catch (_) {}
  }

  void _setChannels(List<Channel> channels) {
    if (channels.isEmpty) {
      _shelfEpoch++;
      _swap(CatalogShelf.empty());
      return;
    }
    unawaited(_installChannels(channels));
  }

  Timer? _prewarmTimer;

  /// Builds the Film/Serie TV lists in small steps while the user is still on
  /// the Home, so opening those tabs (above all right after launch) no longer
  /// waits for the whole playlist to be grouped.
  void _schedulePrewarm() {
    _prewarmTimer?.cancel();
    if (_shelf.isEmpty) return;
    // TV boxes: the first half minute belongs to the Home and the remote;
    // grouping tens of thousands of titles there froze input after launch.
    _prewarmTimer = Timer(
      DeviceTypeService.isTv
          ? const Duration(seconds: 2)
          : const Duration(seconds: 4),
      () => unawaited(_prewarm()),
    );
  }

  Future<void> _prewarm() async {
    if (_playbackActive || !ForegroundPolicy.instance.active) {
      _prewarmTimer = Timer(
        const Duration(seconds: 10),
        () => unawaited(_prewarm()),
      );
      return;
    }
    final epoch = _shelfEpoch;
    if (_shelf.isEmpty) return;
    for (final type in [
      ContentType.live,
      ContentType.movie,
      ContentType.series,
      ContentType.anime,
    ]) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (epoch != _shelfEpoch || _disposed) return;
      await ensureCatalogPrepared(type);
    }
    if (!_playbackActive && ForegroundPolicy.instance.active) {
      _startCatalogIndex();
    }
  }

  /// Bumped when new TMDB genres arrive, so pages can cache what they derive
  /// from them (e.g. the genre bar) between two updates.
  int _titleInfoVersion = 0;
  int get titleInfoVersion => _titleInfoVersion;

  void _applyAdultFilter() {
    _rebuildMask();
    final published = _groupedCache.isNotEmpty || _typedViews.isNotEmpty;
    if (!published && !_shelf.isEmpty) {
      _publishShelf();
    } else {
      notifyListeners();
    }
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
        final clock = Stopwatch()..start();
        _titleInfoVersion++;
        if (_kidsMode) _applyAdultFilter();
        for (final type in _groupedCache.keys.toList()) {
          unawaited(_ensureGenreCounts(type));
        }
        notifyListeners();
        FrameTelemetryService.instance.recordWork('bambini.aggiorna', clock);
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

  /// True for pornographic items: "XXX" or "for adults" in the title or
  /// category, plus well known adult channel brands and keywords.
  static bool isAdult(Channel c) => catalogChannelIsAdult(c);

  List<String> groupsOf(ContentType type) {
    final labels = [..._shelf.categoryLabels(type)]..sort();
    return labels;
  }

  /// Category labels in the playlist's own order (not alphabetical).
  List<String> categoryOrderOf(ContentType type) => _shelf.categoryLabels(type);

  /// Categories the user hid per type (key: content type name).
  Map<String, List<String>> get hiddenCategories => _hiddenCategories;

  List<String> hiddenCategoriesOf(ContentType type) =>
      _hiddenCategories[type.name] ?? const [];

  Future<void> setHiddenCategories(
    ContentType type,
    List<String> hidden,
  ) async {
    _hiddenCategories = {..._hiddenCategories, type.name: hidden};
    _preparationEpoch++;
    _preparing.clear();
    _groupedCache.remove(type);
    _genreCountsCache.remove(type);
    _genreCountsVersions.remove(type);
    _allCache.remove(type);
    _recentCache.remove(type);
    notifyListeners();
    await _settingsService.setHiddenCategories(_hiddenCategories);
  }

  /// Catalog grouped by category, preserving the playlist's category order,
  /// with duplicates removed and hidden categories excluded. Personal
  /// categories come first; the user's saved order then wins over both.
  List<CatalogGroup> groupedCatalog(ContentType type) {
    final ready = _groupedCache[type];
    if (ready != null) return ready;
    unawaited(ensureCatalogPrepared(type));
    return const [];
  }

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
    _preparationEpoch++;
    _preparing.clear();
    _groupedCache.remove(type);
    _genreCountsCache.remove(type);
    _genreCountsVersions.remove(type);
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
    return [for (final id in category.itemIds) ?byId[id]];
  }

  /// Recently added items of a type, in the playlist's own order (the
  /// provider lists newest entries last, so newest-first means reversed).
  /// "Ultimi Aggiunti": the 100 newest items by the provider's added date
  /// (playlist order as tie-breaker, newest entries come last there).
  List<CatalogEntry> recentEntries(ContentType type, {int limit = 100}) {
    final ready = _recentCache[type];
    if (ready == null) {
      unawaited(ensureCatalogPrepared(type));
      return const [];
    }
    return ready.length <= limit
        ? ready
        : ready.take(limit).toList(growable: false);
  }

  /// "Visti di recente": up to [limit] titles of [type] watched or started,
  /// newest first. Episodes count for their series.
  List<CatalogEntry> recentlyWatchedEntries(
    ContentType type,
    List<HistoryEntry> history, {
    int limit = 100,
  }) {
    final token = _historyToken(history);
    final cached = _watchedMemos[type];
    if (cached != null &&
        cached.token == token &&
        cached.kids == _kidsMode &&
        cached.version == _titleInfoVersion &&
        cached.epoch == _shelfEpoch &&
        cached.limit == limit) {
      return cached.entries;
    }
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
    _watchedMemos[type] = _RecentWatchMemo(
      token: token,
      kids: _kidsMode,
      version: _titleInfoVersion,
      epoch: _shelfEpoch,
      limit: limit,
      entries: out,
    );
    return out;
  }

  static int _historyToken(List<HistoryEntry> history) {
    var token = history.length;
    for (final entry in history) {
      token = Object.hash(
        token,
        entry.contentId,
        entry.type.index,
        entry.seriesKey,
        entry.lastWatchedAt.microsecondsSinceEpoch,
      );
    }
    return token;
  }

  /// Basic handling: every playlist item is played as it is, no merging of
  /// copies with different quality (that matching opened the wrong title).
  List<Channel> variantsFor(Channel channel) => [channel];

  List<Channel> get favorites =>
      _favoritesCache ??= [for (final id in _favoriteIds) ?channelById(id)];

  /// TMDB genre ids of a playlist movie/series (null while not checked yet).
  List<int>? genresOf(Channel c) => _kids.genresOf(c);

  /// Read-only UI access: never walks the catalog while opening a filter.
  Map<int, int> genreCountsOf(ContentType type) {
    return _genreCountsCache[type] ?? const {};
  }

  Future<void> _ensureGenreCounts(ContentType type) {
    final running = _genreCountJobs[type];
    if (running != null) return running;
    final groups = _groupedCache[type];
    if (groups == null ||
        _disposed ||
        _genreCountsVersions[type] == _titleInfoVersion) {
      return Future<void>.value();
    }
    final epoch = _preparationEpoch;
    final version = _titleInfoVersion;
    bool current() =>
        !_disposed &&
        epoch == _preparationEpoch &&
        version == _titleInfoVersion &&
        identical(groups, _groupedCache[type]);
    late final Future<void> job;
    job =
        () async {
          await _kids.load();
          final work = CatalogYield(
            () async =>
                current() &&
                !_playbackActive &&
                ForegroundPolicy.instance.active,
          );
          final counts = <int, int>{};
          try {
            if (!current() ||
                _playbackActive ||
                !ForegroundPolicy.instance.active) {
              return;
            }
            for (final group in groups) {
              for (final entry in group.entries) {
                final slot = entry.shelfSlot;
                final key = slot == null
                    ? KidsContentService.keyOf(entry.primary)
                    : _shelf.facetKeyAt(slot);
                for (final id in _kids.genresForKey(key) ?? const <int>[]) {
                  counts[id] = (counts[id] ?? 0) + 1;
                }
                await work.step();
              }
            }
            if (!current() ||
                _playbackActive ||
                !ForegroundPolicy.instance.active) {
              return;
            }
            _genreCountsCache[type] = Map.unmodifiable(counts);
            _genreCountsVersions[type] = version;
            notifyListeners();
          } on CatalogPreparationCancelled {
            // Retry on the next eligible filter access; never publish stale counts.
          }
        }().whenComplete(() {
          if (identical(_genreCountJobs[type], job)) {
            _genreCountJobs.remove(type);
          }
        });
    _genreCountJobs[type] = job;
    return job;
  }

  /// Asks the background TMDB check for genres of exactly these titles (the
  /// catalog cards), so the genre bar fills for series folders too.
  void requestTitleInfo(Iterable<Channel> items) =>
      unawaited(_kids.warmUp(items));

  /// Drawer counts never sort or initiate title preparation.
  int catalogCountOf(ContentType type) => _allCache[type]?.length ?? 0;

  List<CatalogEntry> allEntries(ContentType type) {
    final ready = _allCache[type];
    if (ready != null) return ready;
    unawaited(ensureCatalogPrepared(type));
    return const [];
  }

  final Map<ContentType, List<CatalogEntry>> _allCache = {};

  bool get catalogIndexReady => _shelfReady;

  int get catalogIndexRevision => _shelfEpoch * 2 + (_shelfReady ? 1 : 0);

  final Map<String, Channel?> _matchCache = {};

  int get searchStamp => Object.hash(_shelfEpoch, _visibleCount, _shelfReady);

  /// Prefix lookup. The posting lists are built with the shelf, so a query
  /// does not walk every title.
  List<CatalogEntry> queryEntries(
    ContentType type,
    String query, {
    String? group,
  }) {
    final wanted = type.index;
    final out = <CatalogEntry>[];
    final seen = <int>{};
    for (final slot in _shelf.searchSlots(query)) {
      if (slot >= _visibleMask.length || _visibleMask[slot] == 0) continue;
      if (_shelf.typeIndexAt(slot) != wanted) continue;
      if ((type == ContentType.series || type == ContentType.anime) &&
          !_shelf.isFolderSlot(slot)) {
        continue;
      }
      if (group != null && _shelf.groupAt(slot) != group) continue;
      if (seen.add(slot)) out.add(_slotEntry(slot));
    }
    return out;
  }

  Future<Map<ContentType, List<Channel>>> searchCatalog(String query) async {
    final q = query.trim();
    if (q.isEmpty || _disposed || _shelf.isEmpty) return const {};
    final buckets = {for (final type in ContentType.values) type: <Channel>[]};
    for (final slot in _shelf.searchSlots(q)) {
      if (slot >= _visibleMask.length || _visibleMask[slot] == 0) continue;
      final type = ContentType.values[_shelf.typeIndexAt(slot)];
      if ((type == ContentType.series || type == ContentType.anime) &&
          !_shelf.isFolderSlot(slot)) {
        continue;
      }
      final list = buckets[type]!;
      if (list.length >= 40) continue;
      list.add(_shelf.readSlot(slot));
    }
    return buckets;
  }

  /// Live ids inside [among] answered by the shelf prefix index.
  Set<String> matchingChannelIds(
    ContentType type,
    String query,
    Set<String> among,
  ) {
    if (!_shelfReady || query.trim().length < 2 || among.isEmpty) {
      return const {};
    }
    return _shelf.idsMatching(query, typeIndex: type.index, among: among);
  }

  Future<List<Map<String, String>>> liveIdentities() => _shelf.liveIdentities();

  void _startCatalogIndex() {}

  Channel? seriesFolderFor(String seriesKey, {bool wait = true}) {
    if (!_shelfReady) return null;
    final slot = _shelf.folderSlot(seriesKey);
    if (slot == null ||
        slot >= _visibleMask.length ||
        _visibleMask[slot] == 0) {
      return null;
    }
    return _shelf.readSlot(slot);
  }

  bool isAvailable(TmdbItem item) => findChannelFor(item, wait: false) != null;

  bool isTmdbAllowed(TmdbItem item) {
    if (!_kidsMode) return true;
    final channel = findChannelFor(item);
    return channel != null &&
        isKidsContent(channel) &&
        !KidsContentService.bannedKeywords.hasMatch(
          '${item.title} ${item.overview}',
        );
  }

  Channel? findChannelFor(TmdbItem item, {bool wait = true}) {
    if (_matchCache.containsKey(item.key)) return _matchCache[item.key];
    if (!_shelfReady) return null;
    final result = _findChannelFor(item);
    _matchCache[item.key] = result;
    return result;
  }

  Channel? _findChannelFor(TmdbItem item) {
    final target = _titleKey(item.title);
    if (target.isEmpty) return null;
    final isMovie = item.contentType == ContentType.movie;
    final candidates = <Channel>[];
    for (final slot in _shelf.exactSlots(target)) {
      if (slot >= _visibleMask.length || _visibleMask[slot] == 0) continue;
      final channel = _shelf.readSlot(slot);
      final movie = channel.type == ContentType.movie;
      if (isMovie == movie) candidates.add(channel);
    }
    if (candidates.isEmpty) return null;
    final year = item.year;
    if (year.isNotEmpty) {
      Channel? sameYear;
      final noYear = <Channel>[];
      for (final channel in candidates) {
        final found = _yearOf(channel.name);
        if (found == year) {
          sameYear ??= channel;
        } else if (found == null) {
          noYear.add(channel);
        }
      }
      if (sameYear != null) return sameYear;
      return noYear.firstOrNull;
    }
    return candidates.first;
  }

  static final _yearPattern = RegExp(r'\b(19|20)\d{2}\b');
  static String? _yearOf(String name) =>
      _yearPattern.firstMatch(name)?.group(0);

  /// Title key without language prefix, brackets, quality tags and year.
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
        final local = SeriesGrouping.detailsFromEpisodes(
          series,
          _shelf.episodesOf(series),
        );
        if (local.seasons.isNotEmpty) return _safeSeriesDetails(local);
        rethrow;
      }
    }
    return _safeSeriesDetails(
      SeriesGrouping.detailsFromEpisodes(series, _shelf.episodesOf(series)),
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
    // Saved genres are read off the UI thread right away, so genre filters
    // and title facets work from the first screen, not after the warm-up.
    unawaited(_kids.load().then((_) => notifyListeners()).catchError((_) {}));
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
      final key = _cacheKey(credentials);
      if (await _catalogCache.hasSectionFile(key)) {
        await _installFromFiles(key);
      } else {
        final cached = await _catalogCache.read(key);
        if (cached.isNotEmpty && _shelf.isEmpty) await _installChannels(cached);
      }
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
        if (_fullLoadActive || _anyPending) {
          // A full download is already queued. The saved index is enough
          // to open the sections that are already on the device.
        } else if (missing.length == _playlistTypes.length) {
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
    if (_fullLoadActive || _anyPending) return;
    _fullLoadActive = true;
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
      _fullLoadActive = false;
      _finishIfIdle();
    }
  }

  Future<bool> loginWithXtream({
    required String server,
    required String username,
    required String password,
    SourceLoginResult? verified,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = verified != null && verified.ok
          ? verified
          : await _xtreamService.authenticate(
              server: server,
              username: username,
              password: password,
            );
      if (!result.ok) {
        _error = result.message;
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
  final List<String> _loadFailures = [];

  bool get _anyPending => _catalogStates.values.any((s) => s.isPending);

  String get _currentKey => _cacheKey(_xtreamCredentials ?? const {});

  /// Retries one section only; the other sections keep their content.
  Future<void> retrySection(ContentType type, {bool force = false}) async {
    final section = type == ContentType.anime ? ContentType.series : type;
    final credentials = _xtreamCredentials;
    if (!ForegroundPolicy.instance.active ||
        credentials == null ||
        catalogState(section).isPending) {
      return;
    }
    if (!force && (_fullLoadActive || _anyPending) && _hasSection(section)) {
      return;
    }
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
    if (_fullLoadActive || _anyPending) return;
    _fullLoadActive = true;
    try {
      await Future.wait([
        for (final t in const [
          ContentType.live,
          ContentType.movie,
          ContentType.series,
        ])
          retrySection(t, force: true),
      ]);
    } finally {
      _fullLoadActive = false;
    }
    if (_loadFailures.isEmpty) {
      await _refreshService.markRun();
      _playlistRefreshRevision++;
      notifyListeners();
    }
    await _refreshService.schedule();
  }

  /// Never true during playback, so the wait screen cannot cover a video.
  bool get isRefreshingAny =>
      _anyPending && !_playbackActive && (!_startupLoading || _shelf.isEmpty);

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
        if (ForegroundPolicy.instance.active && !done.isCompleted) {
          done.complete();
        }
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
      final saved = await _persistSectionCopy(key, type, channels);
      if (_disposed || key != _currentKey) return;
      if (_playbackActive || !ForegroundPolicy.instance.active) {
        // A video is playing: swapping the catalog now re-filters and
        // rebuilds every page under the player. Keep the section aside.
        _pendingSections[type] = channels;
      } else if (saved && await _catalogCache.hasSectionFile(key)) {
        await _installFromFiles(key, changed: type);
        FrameTelemetryService.instance.mark(
          'catalogo: pubblicato ${type.name}',
        );
      } else {
        await _publishResolved(type, channels, key);
        FrameTelemetryService.instance.mark(
          'catalogo: pubblicato ${type.name}',
        );
      }
      _catalogStates[type] = CatalogLoadState(
        phase: CatalogLoadPhase.ready,
        hasContent: channels.isNotEmpty,
      );
    } catch (e) {
      if (_disposed || key != _currentKey) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      _loadFailures.add(message);
      if (!_hasSection(type)) {
        if (await _catalogCache.hasSectionFile(key)) {
          await _installFromFiles(key, changed: type);
        } else {
          final cached = await _catalogCache.read(key);
          if (_disposed || key != _currentKey) return;
          final fallback = [
            for (final channel in cached)
              if (_belongsToSection(channel, type)) channel,
          ];
          if (fallback.isNotEmpty) await _publishResolved(type, fallback, key);
        }
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
    _error = _shelf.isEmpty && _loadFailures.isNotEmpty
        ? _loadFailures.first
        : null;
    _loadFailures.clear();
    notifyListeners();
  }

  Future<void> loadFromXtream({
    required String server,
    required String username,
    required String password,
  }) async {
    final requestedKey = _cacheKey({'server': server, 'username': username});
    if (_fullLoadActive || (_anyPending && requestedKey == _activeLoadKey)) {
      return;
    }
    _fullLoadActive = true;
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
        _playlistRefreshRevision++;
        notifyListeners();
      }
    } finally {
      _fullLoadActive = false;
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
    _pendingCatalogWrites.clear();
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
    _titleCategoriesTimer?.cancel();
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
    _shelf.close();
    super.dispose();
  }
}

class _RecentWatchMemo {
  const _RecentWatchMemo({
    required this.token,
    required this.kids,
    required this.version,
    required this.epoch,
    required this.limit,
    required this.entries,
  });

  final int token;
  final bool kids;
  final int version;
  final int epoch;
  final int limit;
  final List<CatalogEntry> entries;
}
