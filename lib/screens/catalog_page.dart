import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../navigation/app_routes.dart';
import '../providers/app_provider.dart';
import '../providers/ui_settings.dart';
import '../services/catalog_builder.dart';
import '../services/device_type_service.dart';
import '../theme/app_theme.dart';
import '../widgets/channel_card.dart';
import '../widgets/tv_category_panel.dart';
import '../widgets/section_row.dart';
import 'settings_screen.dart';

SliverGridDelegate channelGridDelegate(
  ContentType type, {
  double maxExtent = 140,
  bool compact = false,
}) {
  final isLive = type == ContentType.live;
  if (DeviceTypeService.isTv) {
    return SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: isLive ? 180 : 132,
      childAspectRatio: isLive ? 1.05 : 0.6,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
    );
  }
  return SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: isLive ? 150 : (compact ? maxExtent * 0.86 : maxExtent),
    childAspectRatio: isLive ? 0.9 : (compact ? 0.62 : 0.58),
    crossAxisSpacing: compact ? 8 : 12,
    mainAxisSpacing: compact ? 10 : 16,
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
    final card = ChannelCard(
      channel: primary,
      isFavorite: isFavorite,
      onTap: onTap,
      onFavoriteTap: onFavoriteTap,
    );
    if (quality == null) return card;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          top: 6,
          left: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              quality,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ],
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
    return GridView.builder(
      padding: padding,
      gridDelegate: channelGridDelegate(
        type,
        maxExtent: ui.gridMaxExtent,
        compact: ui.compact,
      ),
      itemCount: channels.length,
      itemBuilder: (context, i) {
        final c = channels[i];
        return ChannelCard(
          channel: c,
          isFavorite: app.favoriteIds.contains(c.id),
          onTap: () => openChannel(context, c),
          onFavoriteTap: () => app.toggleFavorite(c),
        );
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
  FocusNode? _drawerReturn;
  void _openCategories() {
    _drawerReturn = FocusManager.instance.primaryFocus;
    _scaffoldKey.currentState?.openDrawer();
  }

  void _closeCategories() => _scaffoldKey.currentState?.closeDrawer();
  void _drawerChanged(bool opened) {
    if (opened || !DeviceTypeService.isTv) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _drawerReturn;
      if (target != null && target.context != null) target.requestFocus();
    });
  }

  String _query = '';
  String? _selectedCategory;
  int? _genreId;
  bool _infoRequested = false;

  static const _recentLabel = 'Ultimi Aggiunti';
  String get _allLabel =>
      widget.type == ContentType.movie ? 'Tutti i Film' : 'Tutte le Serie';
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String get _noun => switch (widget.type) {
    ContentType.live => 'canali',
    ContentType.movie => 'film',
    ContentType.series => 'serie',
    ContentType.anime => 'anime',
  };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();

    if (app.catalogState(widget.type).isPending &&
        !app.catalogState(widget.type).hasContent) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (app.catalogState(widget.type).error != null &&
        !app.catalogState(widget.type).hasContent) {
      return EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Impossibile caricare la playlist',
        message:
            app.catalogState(widget.type).error ?? 'Caricamento non riuscito',
        action: ElevatedButton.icon(
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Riprova'),
          onPressed: app.isAuthenticated ? app.refreshPlaylist : null,
        ),
      );
    }

    final groups = app.groupedCatalog(widget.type);
    if (groups.isEmpty) {
      return EmptyState(
        icon: Icons.playlist_add_rounded,
        title: 'Nessun contenuto',
        message: 'La tua playlist non contiene $_noun.',
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
      app.requestTitleInfo(app.catalogOf(widget.type));
    }

    final selected = _selectedCategory;
    final showAll = selected == _allLabel;
    final visibleGroup = selected == null || showAll
        ? null
        : groups.where((g) => g.label == selected).firstOrNull;

    return Scaffold(
      key: _scaffoldKey,
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: 48,
      onDrawerChanged: _drawerChanged,
      drawer: DeviceTypeService.isTv
          ? TvCategoryPanel(
              categories: {
                _recentLabel: app.recentEntries(widget.type).length,
                _allLabel: app.allEntries(widget.type).length,
                for (final g in groups)
                  if (g.label != _allLabel) g.label: g.entries.length,
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
                _recentLabel: app.recentEntries(widget.type).length,
                _allLabel: app.allEntries(widget.type).length,
                for (final g in groups)
                  if (g.label != _allLabel) g.label: g.entries.length,
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Cerca tra $_noun',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Categorie',
                  icon: const Icon(Icons.category_outlined),
                  onPressed: _openCategories,
                ),
              ],
            ),
          ),
          _buildGenreBar(app, groups),
          Expanded(
            child: _query.isNotEmpty
                ? _buildSearchResults(app)
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

  bool _matchesGenre(AppProvider app, CatalogEntry e) {
    final id = _genreId;
    if (id == null) return true;
    return app.genresOf(e.primary)?.contains(id) ?? false;
  }

  /// One-genre chip bar; only genres that exist in the playlist are shown.
  Widget _buildGenreBar(AppProvider app, List<CatalogGroup> groups) {
    final names = _genreNames;
    final counts = <int, int>{};
    for (final g in groups) {
      for (final e in g.entries) {
        for (final id in app.genresOf(e.primary) ?? const <int>[]) {
          if (names.containsKey(id)) counts[id] = (counts[id] ?? 0) + 1;
        }
      }
    }
    if (counts.isEmpty) return const SizedBox.shrink();
    final ids = counts.keys.toList()
      ..sort((a, b) => names[a]!.compareTo(names[b]!));
    Widget chip(String label, bool selected, VoidCallback onTap) => Padding(
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
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
          if (_matchesGenre(app, e) && seen.add(e.primary.id)) e,
    ];
  }

  Widget _buildRecentGrid(AppProvider app) {
    final entries = _genreId != null
        ? _allOfGenre(app)
        : app.recentEntries(widget.type);
    if (entries.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nessun risultato',
        message: 'Prova con un altro titolo o categoria.',
      );
    }
    final ui = context.watch<UiSettings>();
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: channelGridDelegate(
        widget.type,
        maxExtent: ui.gridMaxExtent,
        compact: ui.compact,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) => _entryCard(app, entries[i]),
    );
  }

  Widget _buildAllGrid(AppProvider app) {
    final ui = context.watch<UiSettings>();
    final entries = app
        .allEntries(widget.type)
        .where((e) => _matchesGenre(app, e))
        .toList();
    if (entries.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nessun risultato',
        message: 'Nessun titolo di questo genere.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: channelGridDelegate(
        widget.type,
        maxExtent: ui.gridMaxExtent,
        compact: ui.compact,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) => _entryCard(app, entries[i]),
    );
  }

  Widget _buildGroupGrid(AppProvider app, CatalogGroup group) {
    final ui = context.watch<UiSettings>();
    final entries = group.entries.where((e) => _matchesGenre(app, e)).toList();
    if (entries.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nessun risultato',
        message: 'Nessun titolo di questo genere nella categoria.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: channelGridDelegate(
        widget.type,
        maxExtent: ui.gridMaxExtent,
        compact: ui.compact,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) => _entryCard(app, entries[i]),
    );
  }

  Widget _buildSearchResults(AppProvider app) {
    final q = _query.toLowerCase();
    final matches = <CatalogEntry>[];
    final seen = <String>{};
    for (final g in app.groupedCatalog(widget.type)) {
      for (final e in g.entries) {
        if (!e.primary.name.toLowerCase().contains(q)) continue;
        if (!_matchesGenre(app, e)) continue;
        final key = e.primary.id;
        if (seen.contains(key)) continue;
        seen.add(key);
        matches.add(e);
      }
    }
    if (matches.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nessun risultato',
        message: 'Prova con un altro titolo o categoria.',
      );
    }
    final ui = context.watch<UiSettings>();
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: channelGridDelegate(
        widget.type,
        maxExtent: ui.gridMaxExtent,
        compact: ui.compact,
      ),
      itemCount: matches.length,
      itemBuilder: (context, i) => _entryCard(app, matches[i]),
    );
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
