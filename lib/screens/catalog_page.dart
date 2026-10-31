import 'dart:async';

import '../services/catalog_sort.dart';
import '../services/catalog_order_store.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../navigation/app_routes.dart';
import '../providers/app_provider.dart';
import '../services/catalog_index_builder.dart' show catalogEntryKey;
import '../providers/history_provider.dart';
import '../providers/ui_settings.dart';
import '../services/catalog_builder.dart';
import '../services/device_type_service.dart';
import '../services/frame_telemetry_service.dart';
import '../theme/app_theme.dart';
import '../widgets/channel_card.dart';
import '../widgets/catalog_layouts.dart';
import '../widgets/settings_tiles.dart';
import '../widgets/tv_catalog_toolbar.dart';
import '../widgets/tv_filter_panel.dart';
import '../widgets/tv_catalog_navigation.dart';
import '../widgets/tv_focusable.dart';
import '../services/title_facet_index.dart';
import '../services/image_cache_service.dart';
import '../services/image_warmup_service.dart';
import '../services/platform_catalog_service.dart';
import '../models/streaming_platform.dart';
import '../models/tmdb_item.dart';
import '../providers/discover_provider.dart';
import '../widgets/poster_card.dart';
import '../widgets/title_facets.dart';
import '../widgets/tv_category_panel.dart';
import '../widgets/tv_text_field.dart';
import '../widgets/section_row.dart';
import 'settings_screen.dart';

/// Genre check from the facet already stored on the slot.
bool catalogSlotMatchesGenre(
  AppProvider app,
  CatalogEntry entry,
  int? genreId,
) {
  if (genreId == null) return true;
  final slot = entry.shelfSlot;
  if (slot != null) return app.genresForSlot(slot)?.contains(genreId) ?? false;
  return app.genresOf(entry.primary)?.contains(genreId) ?? false;
}

const catalogName4k = 1;
const catalogNamePlatform = 2;

/// Name checks of the "Solo 4K" and platform filters. Runs in an isolate.
int catalogNameFlags(String name, String? platform, bool only4k) {
  var flags = 0;
  if (only4k && CatalogBuilder.qualityLabel(name) == '4K') {
    flags |= catalogName4k;
  }
  final tagged = StreamingPlatform.byName(platform);
  if (tagged != null && tagged.tagMatches(name)) flags |= catalogNamePlatform;
  return flags;
}

// Top level so the closure sent to the isolate captures only its arguments.
int Function(String) _nameFilter(String? platform, bool only4k) =>
    (name) => catalogNameFlags(name, platform, only4k);

String catalogEntryIdentity(AppProvider app, CatalogEntry entry) {
  final slot = entry.shelfSlot;
  if (slot != null) return app.idAt(slot);
  return catalogEntryKey(entry.primary);
}

SliverGridDelegateWithMaxCrossAxisExtent channelGridDelegate(
  ContentType type, {
  double maxExtent = 140,
  bool compact = false,
}) {
  final isLive = type == ContentType.live;
  if (DeviceTypeService.isTv) {
    // TV honours "Dimensione griglia" (relative to the 'media' size) and
    // "Modalità compatta" too, on top of its larger remote-friendly base.
    final scale = (maxExtent / 140) * (compact ? 0.86 : 1);
    return SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: (isLive ? 180 : 132) * scale,
      childAspectRatio: isLive ? 1.05 : (compact ? 0.62 : 0.6),
      crossAxisSpacing: compact ? 10 : 16,
      mainAxisSpacing: compact ? 10 : 16,
    );
  }
  return SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: isLive ? 150 : (compact ? maxExtent * 0.86 : maxExtent),
    childAspectRatio: isLive ? 0.9 : (compact ? 0.62 : 0.58),
    crossAxisSpacing: compact ? 8 : 12,
    mainAxisSpacing: compact ? 10 : 16,
  );
}

/// Just the next row: Down on the remote finds a tile that is already built.
ScrollCacheExtent? tvCatalogCacheExtent(
  SliverGridDelegateWithMaxCrossAxisExtent delegate,
) {
  if (!DeviceTypeService.isTv) return null;
  return ScrollCacheExtent.pixels(
    delegate.maxCrossAxisExtent / delegate.childAspectRatio +
        delegate.mainAxisSpacing,
  );
}

/// A grid item backed by a deduplicated catalog entry: tapping a title with
/// multiple quality variants asks which copy to play.
class CatalogEntryCard extends StatelessWidget {
  final CatalogEntry entry;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;

  const CatalogEntryCard({
    super.key,
    required this.entry,
    required this.isFavorite,
    required this.onTap,
    required this.onFavoriteTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = entry.primary;
    final quality = CatalogBuilder.qualityLabel(primary.name);
    return ChannelCard(
      channel: primary,
      isFavorite: isFavorite,
      onTap: onTap,
      onFavoriteTap: onFavoriteTap,
      qualityLabel: quality,
    );
  }
}

/// Asks which copy of a title to play when it exists in several qualities.
Future<Channel?> pickVariant(BuildContext context, CatalogEntry entry) async {
  if (entry.variants.length == 1) return entry.primary;
  return showModalBottomSheet<Channel>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'Scegli la versione',
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              entry.primary.displaySeriesName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          for (final v in entry.variants)
            ListTile(
              leading: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  CatalogBuilder.qualityLabel(v.name) ?? 'STD',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              title: Text(
                v.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: v.group != entry.primary.group
                  ? Text(
                      v.group,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    )
                  : null,
              onTap: () => Navigator.pop(ctx, v),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// A plain channel grid, used by search and favorites.
class ChannelGrid extends StatelessWidget {
  final List<Channel> channels;
  final ContentType type;
  final EdgeInsets padding;

  const ChannelGrid({
    super.key,
    required this.channels,
    required this.type,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final ui = context.watch<UiSettings>();
    final delegate = channelGridDelegate(
      type,
      maxExtent: ui.gridMaxExtent,
      compact: ui.compact,
    );
    return GridView.builder(
      padding: padding,
      scrollCacheExtent: tvCatalogCacheExtent(delegate),
      gridDelegate: delegate,
      itemCount: channels.length,
      itemBuilder: (context, i) {
        final c = channels[i];
        final card = ChannelCard(
          channel: c,
          isFavorite: app.favoriteIds.contains(c.id),
          onTap: () => openChannel(context, c),
          onFavoriteTap: () => app.toggleFavorite(c),
        );
        if (!DeviceTypeService.isTv) return card;
        final usable = MediaQuery.sizeOf(context).width - padding.horizontal;
        final columns =
            (usable / (delegate.maxCrossAxisExtent + delegate.crossAxisSpacing))
                .ceil()
                .clamp(1, 100);
        return TvCatalogItem(index: i, columns: columns, child: card);
      },
    );
  }
}

/// TMDB genres (Italian labels). Movie and TV ids differ for a few genres.
const _movieGenres = <int, String>{
  28: 'Azione',
  12: 'Avventura',
  16: 'Animazione',
  35: 'Commedia',
  80: 'Crime',
  99: 'Documentario',
  18: 'Dramma',
  10751: 'Famiglia',
  14: 'Fantasy',
  36: 'Storia',
  27: 'Horror',
  10402: 'Musica',
  9648: 'Mistero',
  10749: 'Romance',
  878: 'Fantascienza',
  53: 'Thriller',
  10752: 'Guerra',
  37: 'Western',
};
const _tvGenres = <int, String>{
  10759: 'Azione e Avventura',
  16: 'Animazione',
  35: 'Commedia',
  80: 'Crime',
  99: 'Documentario',
  18: 'Dramma',
  10751: 'Famiglia',
  10762: 'Bambini',
  9648: 'Mistero',
  10763: 'News',
  10764: 'Reality',
  10765: 'Sci-Fi e Fantasy',
  10766: 'Soap',
  10767: 'Talk show',
  10768: 'Guerra e Politica',
  37: 'Western',
};

class CatalogPage extends StatefulWidget {
  final ContentType type;

  const CatalogPage({super.key, required this.type});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final TextEditingController _searchController = TextEditingController();
  FocusNode? _drawerReturn;
  bool _drawerOpen = false;
  void _openCategories() {
    _drawerReturn = FocusManager.instance.primaryFocus;
    _scaffoldKey.currentState?.openDrawer();
  }

  void _closeCategories() => _scaffoldKey.currentState?.closeDrawer();
  void _drawerChanged(bool opened) {
    if (mounted && _drawerOpen != opened) setState(() => _drawerOpen = opened);
    if (opened || !DeviceTypeService.isTv) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _drawerReturn;
      if (target != null && target.context != null) target.requestFocus();
    });
  }

  CatalogSort? _sort = CatalogSort.provider;
  bool _sorting = false;
  List<CatalogEntry>? _requestedSortSource;
  List<CatalogEntry>? _recentSnapshot;
  Object? _recentGroups;
  List<CatalogEntry> _recent(AppProvider app) {
    final groups = app.groupedCatalog(widget.type);
    if (!identical(groups, _recentGroups)) {
      _recentGroups = groups;
      _recentSnapshot = app.recentEntries(widget.type);
    }
    if ((_recentSnapshot?.isEmpty ?? true) &&
        app.catalogPreparing(widget.type)) {
      _recentSnapshot = app.recentEntries(widget.type);
    }
    return _recentSnapshot ?? const [];
  }

  List<CatalogEntry>? _sortedSource;
  List<CatalogEntry>? _sortedEntries;
  CatalogSort? _sortedOrder;
  List<String>? _publishedIds;
  int _publishedRank = -1;
  String? _ratingKey;
  Timer? _ratingDebounce;
  String _query = '';
  String? _selectedCategory;
  int? _genreId;
  StreamingPlatform? _platform;

  /// "Solo 4K": keeps titles with at least one 4K/UHD copy. Combinable
  /// with a platform and a genre.
  bool _only4k = false;
  Set<String>? _platformIds;
  String? _platformIdsKey;
  bool _infoRequested = false;

  static const _recentLabel = 'Ultimi Aggiunti';
  static const _watchedLabel = 'Visti di recente';
  String get _allLabel =>
      widget.type == ContentType.movie ? 'Tutti i film' : 'Tutte le serie TV';
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String get _noun => switch (widget.type) {
    ContentType.live => 'canali',
    ContentType.movie => 'film',
    ContentType.series => 'serie',
    ContentType.anime => 'anime',
  };

  @override
  void initState() {
    super.initState();
    PlatformCatalogService.instance.addListener(_platformsChanged);
    CatalogOrderStore.instance.addListener(_savedOrderLoaded);
    TitleFacetIndex.instance.addListener(_onFacetRank);
    unawaited(CatalogOrderStore.instance.load());
  }

  /// A newer score list waits until the remote is still, so the grid does
  /// not jump under the thumb. The sort button itself does not wait.
  void _onFacetRank() {
    if (!mounted || _sort != CatalogSort.rating) return;
    final generation = TitleFacetIndex.instance.generationOf(widget.type);
    if (generation == _publishedRank) return;
    _ratingDebounce?.cancel();
    _ratingDebounce = Timer(const Duration(milliseconds: 900), () async {
      await RemoteNavigation.idle();
      if (!mounted || _sort != CatalogSort.rating) return;
      setState(_publishRatingIds);
    });
  }

  void _publishRatingIds() {
    final ids = TitleFacetIndex.instance.idsFor(widget.type);
    _publishedRank = TitleFacetIndex.instance.generationOf(widget.type);
    _publishedIds = ids == null ? null : List<String>.from(ids);
    _sortedSource = null;
    _sortedEntries = null;
  }

  void _savedOrderLoaded() {
    if (!mounted || _sort != CatalogSort.rating || _publishedIds != null) {
      return;
    }
    setState(() {
      _sortedSource = null;
      _sortedEntries = null;
    });
  }

  void _platformsChanged() {
    if (mounted && _platform != null) setState(() {});
  }

  bool get _platformMovies => widget.type == ContentType.movie;

  void _selectPlatform(StreamingPlatform? platform) {
    setState(() => _platform = _platform == platform ? null : platform);
    final chosen = _platform;
    if (chosen != null) {
      PlatformCatalogService.instance.ensure(
        context.read<DiscoverProvider>().tmdb,
        chosen,
        movies: _platformMovies,
      );
    }
  }

  String _platformKey(AppProvider app, StreamingPlatform p) =>
      '${p.name}:${PlatformCatalogService.instance.version}:'
      '${identityHashCode(app.allChannels)}:${app.catalogIndexRevision}';

  /// Playlist ids TMDB lists for the selected platform (matched locally).
  Set<String> _platformMatches(AppProvider app, StreamingPlatform p) {
    final service = PlatformCatalogService.instance;
    final key = _platformKey(app, p);
    if (_platformIds != null && _platformIdsKey == key) return _platformIds!;
    final ids = <String>{};
    for (final item
        in service.itemsOf(p, movies: _platformMovies) ?? const <TmdbItem>[]) {
      final match = app.findChannelFor(item);
      if (match != null) ids.add(match.id);
    }
    _platformIdsKey = key;
    return _platformIds = ids;
  }

  static bool _is4k(CatalogEntry e) =>
      e.variants.any((c) => CatalogBuilder.qualityLabel(c.name) == '4K');

  List<String> get _activeFilterLabels => [
    if (_genreId != null && _genreNames[_genreId] != null)
      _genreNames[_genreId]!,
    if (_platform != null) _platform!.name,
    if (_only4k) '4K',
  ];

  Widget _buildPlatformPanel() => TvFilterPanel(
    options: [
      TvFilterOption(
        'Solo 4K',
        _only4k,
        () => setState(() => _only4k = !_only4k),
      ),
      TvFilterOption(
        'Tutte le piattaforme',
        _platform == null,
        () => _selectPlatform(null),
      ),
      for (final p in StreamingPlatform.all)
        TvFilterOption(
          PlatformCatalogService.instance.isLoading(p, movies: _platformMovies)
              ? '${p.name} · caricamento…'
              : p.name,
          _platform == p,
          () => _selectPlatform(p),
          brandColor: p.color,
        ),
    ],
  );

  Future<void> _pickPlatformMobile() async {
    const none = 'Tutte le piattaforme';
    final chosen = await pickOption<String>(
      context,
      title: 'Piattaforme streaming',
      options: [
        _only4k ? 'Solo 4K ✓' : 'Solo 4K',
        none,
        for (final p in StreamingPlatform.all) p.name,
      ],
      current: _platform?.name ?? none,
      label: (v) => v,
    );
    if (chosen == null || !mounted) return;
    if (chosen.startsWith('Solo 4K')) {
      setState(() => _only4k = !_only4k);
      return;
    }
    final platform = StreamingPlatform.byName(chosen);
    if (platform == _platform) return;
    _selectPlatform(platform);
  }

  @override
  void dispose() {
    _ratingDebounce?.cancel();
    if (_sort == CatalogSort.rating) {
      TitleFacetIndex.instance.watchRank(widget.type, false);
    }
    TitleFacetIndex.instance.removeListener(_onFacetRank);
    CatalogOrderStore.instance.removeListener(_savedOrderLoaded);
    PlatformCatalogService.instance.removeListener(_platformsChanged);
    _searchController.dispose();
    _spotlight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    FrameTelemetryService.instance.countBuild('catalogo ${widget.type.name}');
    final app = context.watch<AppProvider>();

    if (app.catalogState(widget.type).isPending &&
        !app.catalogState(widget.type).hasContent) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (app.catalogState(widget.type).error != null &&
        !app.catalogState(widget.type).hasContent) {
      return EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Impossibile caricare i contenuti',
        message:
            app.catalogState(widget.type).error ?? 'Caricamento non riuscito',
        action: ElevatedButton.icon(
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Riprova'),
          onPressed: app.isAuthenticated
              ? () => app.retrySection(widget.type)
              : null,
        ),
      );
    }

    final groups = app.groupedCatalog(widget.type);
    final anyVisible = groups.any((group) => group.entries.isNotEmpty);
    if (!anyVisible && app.catalogIndexRebuilding) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            const Text(
              'Preparazione del catalogo…',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
          ],
        ),
      );
    }
    if (!anyVisible && !app.catalogPreparing(widget.type)) {
      return EmptyState(
        icon: Icons.playlist_add_rounded,
        title: 'Nessun contenuto',
        message: 'Nessun contenuto disponibile.',
        action: ElevatedButton.icon(
          icon: const Icon(Icons.settings_rounded),
          label: const Text('Apri impostazioni'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
      );
    }

    if (!_infoRequested) {
      _infoRequested = true;
      // Posters of the first visible titles only. The saved index already
      // published the section, so opening the page does not read every title.
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        final provider = this.context.read<AppProvider>();
        final recent = provider.recentEntries(widget.type);
        final decodeWidth = PosterMemoryWarmup.width;
        final posters = [
          for (var i = 0; i < recent.length && i < 24; i++)
            tmdbSizedUrl(recent[i].primary.logo, decodeWidth),
        ];
        ImageWarmupService.warm(posters);
        if (DeviceTypeService.isTv) {
          PosterMemoryWarmup.warmTv(this.context, posters);
        }
      });
    }

    final watched = app.recentlyWatchedEntries(
      widget.type,
      context.watch<HistoryProvider>().entries,
    );
    final selected = _selectedCategory;
    final showAll = selected == _allLabel;
    final showWatched = selected == _watchedLabel;
    final visibleGroup = selected == null || showAll
        ? null
        : groups.where((g) => g.label == selected).firstOrNull;

    return Scaffold(
      key: _scaffoldKey,
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: 48,
      onDrawerChanged: _drawerChanged,
      drawer: !_drawerOpen
          ? const SizedBox(width: 280)
          : DeviceTypeService.isTv
          ? TvCategoryPanel(
              categories: {
                _recentLabel: _recent(app).length,
                _watchedLabel: watched.length,
                _allLabel: app.catalogCountOf(widget.type),
                for (final g in groups)
                  if (g.label != _allLabel && g.entries.isNotEmpty)
                    g.label: g.entries.length,
              },
              selected: _selectedCategory ?? _recentLabel,
              onSelected: (category) => setState(
                () => _selectedCategory = category == _recentLabel
                    ? null
                    : category,
              ),
              onClose: _closeCategories,
            )
          : _CategoryDrawer(
              categories: {
                _recentLabel: _recent(app).length,
                _watchedLabel: watched.length,
                _allLabel: app.catalogCountOf(widget.type),
                for (final g in groups)
                  if (g.label != _allLabel && g.entries.isNotEmpty)
                    g.label: g.entries.length,
              },
              selected: _selectedCategory,
              onSelected: (category) {
                setState(
                  () => _selectedCategory = category == _recentLabel
                      ? null
                      : category,
                );
              },
            ),
      body: catalogColumn(
        children: [
          if (DeviceTypeService.isTv)
            TvCatalogToolbar(
              controller: _searchController,
              hint: 'Cerca tra $_noun',
              category: _selectedCategory ?? _recentLabel,
              onChanged: (v) => setState(() => _query = v),
              sort: _sort,
              onSort: (value) {
                if (_sort == value) return;
                _ratingDebounce?.cancel();
                if (_sort == CatalogSort.rating) {
                  TitleFacetIndex.instance.watchRank(widget.type, false);
                }
                if (value == CatalogSort.rating) {
                  TitleFacetIndex.instance.watchRank(widget.type, true);
                }
                setState(() {
                  _sort = value;
                  if (value == CatalogSort.rating) _publishRatingIds();
                });
              },
              viewMode: context.watch<UiSettings>().viewMode,
              onViewMode: (mode) =>
                  context.read<UiSettings>().setCatalogViewMode(mode),
              scaffoldKey: _scaffoldKey,
              genresOnly: true,
              filters: (_) => _buildTvFilters(app, groups),
              platforms: widget.type == ContentType.live
                  ? null
                  : (_) => _buildPlatformPanel(),
              platformActive: _platform != null || _only4k,
              filterActive: _genreId != null,
              activeFilters: _activeFilterLabels,
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TvTextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'Cerca tra $_noun',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Builder(
                    builder: (context) {
                      final ui = context.watch<UiSettings>();
                      return IconButton(
                        tooltip: 'Disposizione: ${ui.viewMode.label}',
                        icon: Icon(ui.viewMode.icon),
                        onPressed: () async {
                          final chosen = await pickOption<CatalogViewMode>(
                            context,
                            title: 'Disposizione',
                            options: CatalogViewMode.values,
                            current: ui.viewMode,
                            label: (m) => m.label,
                            detail: (m) => m.description,
                          );
                          if (chosen != null) {
                            await ui.setCatalogViewMode(chosen);
                          }
                        },
                      );
                    },
                  ),
                  if (widget.type != ContentType.live)
                    IconButton(
                      tooltip: 'Piattaforme streaming',
                      color: _platform != null || _only4k
                          ? AppColors.primary
                          : null,
                      icon: const Icon(Icons.connected_tv_rounded),
                      onPressed: _pickPlatformMobile,
                    ),
                  IconButton(
                    tooltip: 'Categorie',
                    icon: const Icon(Icons.reorder_rounded),
                    onPressed: _openCategories,
                  ),
                ],
              ),
            ),
          if (!DeviceTypeService.isTv) _buildGenreBar(app, groups),
          Expanded(
            child: _query.isNotEmpty
                ? _buildSearchResults(app)
                : showWatched
                ? _buildWatchedGrid(app, watched)
                : showAll
                ? _buildAllGrid(app)
                : visibleGroup != null
                ? _buildGroupGrid(app, visibleGroup)
                : _buildRecentGrid(app),
          ),
        ],
      ),
    );
  }

  Map<int, String> get _genreNames =>
      widget.type == ContentType.movie ? _movieGenres : _tvGenres;

  // Name flags of the 4K and platform filters, read off the UI isolate.
  // Null while the scan runs: slot entries then match nothing.
  String? _nameFlagsKey;
  Map<int, int>? _nameFlags;
  final Map<String, bool> _groupTags = {};

  bool get _namesPending =>
      (_platform != null || _only4k) && _nameFlags == null;

  Map<int, int>? _nameFlagsFor(AppProvider app) {
    final platform = _platform?.name;
    final only4k = _only4k;
    final key =
        '${widget.type.name}|$platform|$only4k|${app.catalogIndexRevision}';
    if (_nameFlagsKey == key) return _nameFlags;
    _nameFlagsKey = key;
    _nameFlags = null;
    _groupTags.clear();
    app
        .nameFlagsOf(widget.type, _nameFilter(platform, only4k))
        .then(
          (flags) {
            if (mounted && _nameFlagsKey == key) {
              setState(() => _nameFlags = flags);
            }
          },
          onError: (Object error, StackTrace stack) {
            if (mounted && _nameFlagsKey == key) {
              setState(() => _nameFlags = const {});
            }
          },
        );
    return null;
  }

  bool _slotMatchesNames(AppProvider app, int slot) {
    final flags = _nameFlagsFor(app);
    if (flags == null) return false;
    final found = flags[slot] ?? 0;
    if (_only4k && found & catalogName4k == 0) return false;
    final platform = _platform;
    if (platform == null || found & catalogNamePlatform != 0) return true;
    final group = app.groupAt(slot);
    return _groupTags.putIfAbsent(group, () => platform.tagMatches(group)) ||
        _platformMatches(app, platform).contains(app.idAt(slot));
  }

  bool _matchesGenre(AppProvider app, CatalogEntry e) {
    final platform = _platform;
    final id = _genreId;
    if (platform == null && !_only4k) {
      return catalogSlotMatchesGenre(app, e, id);
    }
    final slot = e.shelfSlot;
    if (slot != null) {
      return _slotMatchesNames(app, slot) &&
          catalogSlotMatchesGenre(app, e, id);
    }
    if (platform != null &&
        !belongsToPlatform(
          platform,
          e.primary,
          _platformMatches(app, platform),
        )) {
      return false;
    }
    if (_only4k && !_is4k(e)) return false;
    return catalogSlotMatchesGenre(app, e, id);
  }

  /// One-genre chip bar; only genres that exist in the playlist are shown.
  Widget _buildTvFilters(AppProvider app, List<CatalogGroup> groups) {
    final names = widget.type == ContentType.movie ? _movieGenres : _tvGenres;
    final present = names.keys.toList()
      ..sort((a, b) => (names[a] ?? '').compareTo(names[b] ?? ''));
    return TvFilterPanel(
      options: [
        TvFilterOption(
          'Tutti i generi',
          _genreId == null,
          () => setState(() => _genreId = null),
        ),
        for (final id in present)
          TvFilterOption(
            names[id] ?? '',
            _genreId == id,
            () => setState(() => _genreId = _genreId == id ? null : id),
          ),
      ],
    );
  }

  Widget _buildGenreBar(AppProvider app, List<CatalogGroup> groups) {
    final names = _genreNames;
    final counts = app.genreCountsOf(widget.type);
    if (counts.isEmpty) return const SizedBox.shrink();
    final ids = counts.keys.toList()
      ..sort((a, b) => names[a]!.compareTo(names[b]!));
    Widget chip(String label, bool selected, VoidCallback onTap) {
      final control = Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          showCheckmark: false,
          selectedColor: AppColors.primary.withValues(alpha: 0.22),
          backgroundColor: AppColors.card,
          side: BorderSide(
            color: selected ? AppColors.primary : Colors.transparent,
          ),
          labelStyle: TextStyle(
            fontSize: 13,
            color: selected ? AppColors.primary : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      );
      return DeviceTypeService.isTv
          ? TvFocusable(onPressed: onTap, focusedScale: 1, child: control)
          : control;
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        children: [
          chip(
            'Tutti i generi',
            _genreId == null,
            () => setState(() => _genreId = null),
          ),
          for (final id in ids)
            chip(
              names[id]!,
              _genreId == id,
              () => setState(() => _genreId = _genreId == id ? null : id),
            ),
        ],
      ),
    );
  }

  /// With a genre selected and no category chosen, the whole catalog of
  /// that genre is shown (not only the latest additions).
  List<CatalogEntry> _allOfGenre(AppProvider app) {
    final seen = <String>{};
    return [
      for (final g in app.groupedCatalog(widget.type))
        for (final e in g.entries)
          if (_matchesGenre(app, e) && seen.add(catalogEntryIdentity(app, e)))
            e,
    ];
  }

  /// Titles watched or started, newest first (chronological, not sorted).
  Widget _buildWatchedGrid(AppProvider app, List<CatalogEntry> watched) {
    final entries = watched.where((e) => _matchesGenre(app, e)).toList();
    if (entries.isEmpty) {
      return EmptyState(
        icon: Icons.history_rounded,
        title: 'Nessun titolo visto',
        message: 'Qui trovi gli ultimi 100 $_noun che hai iniziato o visto.',
      );
    }
    return _buildEntries(app, entries);
  }

  Widget _buildRecentGrid(AppProvider app) {
    final entries = _ordered(
      _genreId != null || _platform != null || _only4k
          ? _filtered(
              app,
              app.groupedCatalog(widget.type),
              'recent:filtered-all',
              () => _allOfGenre(app),
            )
          : _recent(app),
    );
    if (entries.isEmpty &&
        (app.catalogPreparing(widget.type) || _namesPending)) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (entries.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nessun risultato',
        message: 'Prova con un altro titolo o categoria.',
      );
    }
    return _buildEntries(app, entries);
  }

  /// Grid (normal or compact) or list, following the layout picker in the
  /// toolbar. The choice is shared by every catalog and remembered.
  Widget _buildEntries(AppProvider app, List<CatalogEntry> entries) {
    final ui = context.watch<UiSettings>();
    if (ui.viewMode == CatalogViewMode.list) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final tile = _CatalogListTile(
            entry: entries[i],
            isFavorite: app.favoriteIds.contains(entries[i].primary.id),
            onTap: () => _openEntry(context, entries[i]),
            onFavoriteTap: () => app.toggleFavorite(entries[i].primary),
          );
          if (!DeviceTypeService.isTv) return tile;
          return TvCatalogItem(
            index: i,
            columns: 1,
            child: TvCategoryEdge(
              scaffoldKey: _scaffoldKey,
              onOpen: _openCategories,
              child: tile,
            ),
          );
        },
      );
    }
    if (ui.viewMode == CatalogViewMode.landscape) {
      final tv = DeviceTypeService.isTv;
      final delegate = SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: (tv ? 380 : 340) * (ui.gridMaxExtent / 140),
        childAspectRatio: 16 / 9,
        crossAxisSpacing: tv ? 18 : 12,
        mainAxisSpacing: tv ? 18 : 12,
      );
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        scrollCacheExtent: tvCatalogCacheExtent(delegate),
        gridDelegate: delegate,
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final e = entries[i];
          final card = CatalogLandscapeCard(
            entry: e,
            isFavorite: app.favoriteIds.contains(e.primary.id),
            onTap: () => _openEntry(context, e),
            onFavoriteTap: () => app.toggleFavorite(e.primary),
          );
          return TvCatalogItem(
            index: i,
            columns: 2,
            child: DeviceTypeService.isTv
                ? TvCategoryEdge(
                    scaffoldKey: _scaffoldKey,
                    onOpen: _openCategories,
                    child: card,
                  )
                : card,
          );
        },
      );
    }
    final dense =
        ui.compact ||
        ui.viewMode == CatalogViewMode.compact ||
        ui.viewMode == CatalogViewMode.spotlight;
    final delegate = channelGridDelegate(
      widget.type,
      maxExtent: ui.viewMode == CatalogViewMode.compact
          ? ui.gridMaxExtent * 0.82
          : ui.gridMaxExtent,
      compact: dense,
    );
    final grid = GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      scrollCacheExtent: tvCatalogCacheExtent(delegate),
      gridDelegate: delegate,
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final item = _gridItem(app, entries[i], i);
        if (ui.viewMode != CatalogViewMode.spotlight) return item;
        // The header follows whichever poster has the remote focus.
        return Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (has) {
            if (has && _spotlight.value?.primary.id != entries[i].primary.id) {
              _spotlight.value = entries[i];
            }
          },
          child: item,
        );
      },
    );
    if (ui.viewMode != CatalogViewMode.spotlight) return grid;
    final current = _spotlight.value;
    if (current == null ||
        !entries.any(
          (e) =>
              catalogEntryIdentity(app, e) ==
              catalogEntryIdentity(app, current),
        )) {
      _spotlight.value = entries.first;
    }
    return Column(
      children: [
        ValueListenableBuilder<CatalogEntry?>(
          valueListenable: _spotlight,
          builder: (_, e, _) => CatalogSpotlightHeader(entry: e),
        ),
        Expanded(child: grid),
      ],
    );
  }

  /// Title shown in the "In evidenza" header.
  final _spotlight = ValueNotifier<CatalogEntry?>(null);

  Widget _buildAllGrid(AppProvider app) {
    final all = app.allEntries(widget.type);
    final entries = _ordered(
      _filtered(
        app,
        all,
        'all',
        () => all.where((e) => _matchesGenre(app, e)).toList(),
      ),
    );
    if (entries.isEmpty &&
        (app.catalogPreparing(widget.type) || _namesPending)) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (entries.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nessun risultato',
        message: 'Nessun titolo di questo genere.',
      );
    }
    return _buildEntries(app, entries);
  }

  Widget _buildGroupGrid(AppProvider app, CatalogGroup group) {
    final entries = _ordered(
      _filtered(
        app,
        group.entries,
        'group:${group.label}',
        () => group.entries.where((e) => _matchesGenre(app, e)).toList(),
      ),
    );
    if (entries.isEmpty &&
        (app.catalogPreparing(widget.type) || _namesPending)) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (entries.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nessun risultato',
        message: 'Nessun titolo di questo genere nella categoria.',
      );
    }
    return _buildEntries(app, entries);
  }

  // Search results are cached per query/filters: focus moves and rating
  // batches rebuild the page but never rescan the whole catalog.
  String? _searchKey;
  List<CatalogEntry>? _searchResult;

  Widget _buildSearchResults(AppProvider app) {
    final q = _query.toLowerCase();
    final key =
        '${app.searchStamp}|$q|$_selectedCategory|$_genreId|'
        '$_platform|$_only4k|${identityHashCode(_nameFlagsFor(app))}|${app.titleInfoVersion}|${app.catalogIndexRevision}|${PlatformCatalogService.instance.version}';
    if (_namesPending) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_searchKey == key && _searchResult != null) {
      final cached = _ordered(_searchResult!);
      return cached.isEmpty
          ? EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Nessun risultato',
              message: 'Prova con un altro titolo o categoria.',
            )
          : _buildEntries(app, cached);
    }
    var matches = app.queryEntries(
      widget.type,
      q,
      group:
          DeviceTypeService.isTv &&
              _selectedCategory != null &&
              _selectedCategory != _allLabel &&
              _selectedCategory != _watchedLabel
          ? _selectedCategory
          : null,
    );
    matches = [
      for (final entry in matches)
        if (_matchesGenre(app, entry)) entry,
    ];
    _searchKey = key;
    _searchResult = matches;
    matches = _ordered(matches);
    if (matches.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nessun risultato',
        message: 'Prova con un altro titolo o categoria.',
      );
    }
    return _buildEntries(app, matches);
  }

  // Remembers the last filtered list so rebuilds (focus moves, rating
  // batches) reuse the same list instance: no re-filtering of huge catalogs
  // and the sort cache in [_ordered] keeps hitting.
  Object? _filterSource;
  String? _filterTag;
  int? _filterGenre;
  String? _filterPlatform;
  int? _filterInfoVersion;
  int? _filterVisibility;
  Map<int, int>? _filterNames;
  List<CatalogEntry>? _filterResult;
  bool _filter4k = false;

  List<CatalogEntry> _filtered(
    AppProvider app,
    Object source,
    String tag,
    List<CatalogEntry> Function() compute,
  ) {
    if (_genreId == null &&
        _platform == null &&
        !_only4k &&
        source is List<CatalogEntry>) {
      return source;
    }
    if (_filterResult != null &&
        identical(_filterSource, source) &&
        _filterTag == tag &&
        _filterGenre == _genreId &&
        _filter4k == _only4k &&
        _filterPlatform ==
            (_platform == null ? null : _platformKey(app, _platform!)) &&
        _filterInfoVersion == app.titleInfoVersion &&
        _filterVisibility == app.visibilityStamp &&
        identical(_filterNames, _nameFlagsFor(app))) {
      return _filterResult!;
    }
    _filterSource = source;
    _filterTag = tag;
    _filterGenre = _genreId;
    _filter4k = _only4k;
    _filterPlatform = _platform == null ? null : _platformKey(app, _platform!);
    _filterInfoVersion = app.titleInfoVersion;
    _filterVisibility = app.visibilityStamp;
    _filterNames = _nameFlagsFor(app);
    final clock = Stopwatch()..start();
    final result = _filterResult = compute();
    FrameTelemetryService.instance.recordWork('catalogo.filtro', clock);
    return result;
  }

  /// One saved order per catalog view: category, genre and filters included,
  /// so changing view does not reuse another list.
  String _ratingOrderKey() =>
      '${widget.type.name}|${_selectedCategory ?? _recentLabel}|'
      '$_genreId|${_platform?.name ?? ''}|$_only4k|$_query';

  List<CatalogEntry> _ordered(List<CatalogEntry> entries) {
    if (!DeviceTypeService.isTv || _sort == null) return entries;
    if (_sort == CatalogSort.rating) return _orderedByRating(entries);
    if (_sort == CatalogSort.provider) return entries;
    _requestedSortSource = entries;
    if (identical(entries, _sortedSource) && _sort == _sortedOrder) {
      return _sortedEntries ?? entries;
    }
    if (!_sorting) {
      _sorting = true;
      final order = _sort!;
      final app = context.read<AppProvider>();
      unawaited(() async {
        List<CatalogEntry>? result;
        try {
          result = await _sortEntries(app, entries, order);
        } catch (error, stack) {
          result = entries;
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'catalog_sort',
            ),
          );
        } finally {
          await RemoteNavigation.idle();
          _sorting = false;
          if (mounted) {
            setState(() {
              if (result != null &&
                  order == _sort &&
                  identical(entries, _requestedSortSource)) {
                _sortedSource = entries;
                _sortedOrder = order;
                _sortedEntries = result;
              }
            });
          }
        }
      }());
    }
    return identical(entries, _sortedSource) && _sort == _sortedOrder
        ? _sortedEntries ?? entries
        : entries;
  }

  /// Shelf titles are sorted by slot: the entries hold the shelf, whose open
  /// files cannot be sent to an isolate, so sending them failed every sort.
  static Future<List<CatalogEntry>> _sortEntries(
    AppProvider app,
    List<CatalogEntry> entries,
    CatalogSort order,
  ) async {
    final bySlot = <int, CatalogEntry>{};
    for (final entry in entries) {
      final slot = entry.shelfSlot;
      if (slot == null) {
        return sortCatalogBackground(
          [
            for (final e in entries)
              CatalogEntry(primary: e.primary, variants: e.variants),
          ],
          order,
          const {},
        );
      }
      bySlot.putIfAbsent(slot, () => entry);
    }
    final sorted = await app.sortSlots(bySlot.keys.toList(), order);
    return [for (final slot in sorted) bySlot[slot]!];
  }

  /// Applies the id list already in memory. No isolate and no remote wait.
  List<CatalogEntry> _orderedByRating(List<CatalogEntry> entries) {
    final key = _ratingOrderKey();
    final ids = _publishedIds;
    final current =
        identical(entries, _sortedSource) &&
        _sortedOrder == CatalogSort.rating &&
        _ratingKey == key &&
        _sortedEntries != null;
    if (current) return _sortedEntries!;
    final saved = ids ?? CatalogOrderStore.instance.idsFor(key);
    _sortedSource = entries;
    _sortedOrder = CatalogSort.rating;
    _ratingKey = key;
    if (saved == null) return _sortedEntries = entries;
    final app = context.read<AppProvider>();
    final clock = Stopwatch()..start();
    // Shelf ids come from the index: reading each title froze the TV.
    final ordered = _sortedEntries = applyCatalogOrder(
      entries,
      saved,
      idOf: (entry) {
        final slot = entry.shelfSlot;
        return slot == null ? entry.primary.id : app.idAt(slot);
      },
    );
    FrameTelemetryService.instance.recordWork('catalogo.ordine', clock);
    return ordered;
  }

  Widget _gridItem(AppProvider app, CatalogEntry entry, int index) =>
      TvCatalogItem(
        index: index,
        columns: _columns(),
        child: _entryCard(app, entry),
      );

  int _columns() {
    final ui = context.read<UiSettings>();
    final delegate = channelGridDelegate(
      widget.type,
      maxExtent: ui.gridMaxExtent,
      compact: ui.compact,
    );
    final width = MediaQuery.sizeOf(context).width - 32;
    return (width / (delegate.maxCrossAxisExtent + delegate.crossAxisSpacing))
        .ceil()
        .clamp(1, 100);
  }

  Widget _entryCard(AppProvider app, CatalogEntry entry) {
    final card = CatalogEntryCard(
      entry: entry,
      isFavorite: app.favoriteIds.contains(entry.primary.id),
      onTap: () => _openEntry(context, entry),
      onFavoriteTap: () => app.toggleFavorite(entry.primary),
    );
    if (!DeviceTypeService.isTv) return card;
    return TvCategoryEdge(
      scaffoldKey: _scaffoldKey,
      onOpen: _openCategories,
      child: card,
    );
  }

  Future<void> _openEntry(BuildContext context, CatalogEntry entry) async {
    final channel = await pickVariant(context, entry);
    if (channel == null || !context.mounted) return;
    openChannel(context, channel);
  }
}

/// One row of the "Lista" layout: small poster, title, category and rating,
/// reachable with the remote like any grid poster.
class _CatalogListTile extends StatelessWidget {
  final CatalogEntry entry;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;

  const _CatalogListTile({
    required this.entry,
    required this.isFavorite,
    required this.onTap,
    required this.onFavoriteTap,
  });

  @override
  Widget build(BuildContext context) {
    final channel = entry.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Pressable(
        onTap: onTap,
        onLongPress: onFavoriteTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: DeviceTypeService.isTv
                  ? AppColors.clear
                  : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 84,
                  child: PosterImage(url: channel.logo),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.displaySeriesName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: DeviceTypeService.isTv ? 16 : 14,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        ChannelRatingBadge(channel),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            channel.group,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: isFavorite
                    ? 'Rimuovi dai preferiti'
                    : 'Aggiungi ai preferiti',
                icon: Icon(
                  isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isFavorite ? AppColors.primary : AppColors.textPrimary,
                  size: 20,
                ),
                onPressed: onFavoriteTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Left-side category panel. Opens with a swipe from the left edge (also on
/// touch devices) or the categories button; on TV remotes, pressing left on
/// the first grid column reaches the edge and opens the drawer.
class _CategoryDrawer extends StatelessWidget {
  final Map<String, int> categories;
  final String? selected;
  final ValueChanged<String> onSelected;

  const _CategoryDrawer({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Categorie',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final entry in categories.entries)
                    ListTile(
                      selected: (selected ?? 'Ultimi Aggiunti') == entry.key,
                      selectedTileColor: AppColors.primary.withValues(
                        alpha: 0.15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      title: Text(
                        entry.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: (selected ?? 'Ultimi Aggiunti') == entry.key
                              ? AppColors.primary
                              : AppColors.textPrimary,
                          fontWeight:
                              (selected ?? 'Ultimi Aggiunti') == entry.key
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      trailing: Text(
                        '(${entry.value})',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      onTap: () {
                        onSelected(entry.key);
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
