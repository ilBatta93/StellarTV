import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/channel.dart';
import '../models/content_type.dart';
import '../navigation/app_routes.dart';
import '../providers/app_provider.dart';
import '../providers/ui_settings.dart';
import '../services/catalog_builder.dart';
import '../theme/app_theme.dart';
import '../widgets/channel_card.dart';
import '../widgets/section_row.dart';
import 'settings_screen.dart';

SliverGridDelegate channelGridDelegate(ContentType type,
    {double maxExtent = 140, bool compact = false}) {
  final isLive = type == ContentType.live;
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
                  color: AppColors.textSecondary, fontSize: 13),
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
                  ? Text(v.group,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11))
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
      gridDelegate: channelGridDelegate(type,
          maxExtent: ui.gridMaxExtent, compact: ui.compact),
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

class CatalogPage extends StatefulWidget {
  final ContentType type;

  const CatalogPage({super.key, required this.type});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  String _query = '';
  String? _selectedCategory;
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

    if (app.isLoading) {
      return Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (app.error != null && app.allChannels.isEmpty) {
      return EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Impossibile caricare la playlist',
        message: app.error!,
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
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
      );
    }

    final selected = _selectedCategory;
    final visibleGroup = selected == null
        ? null
        : groups.where((g) => g.label == selected).firstOrNull;

    return Scaffold(
      key: _scaffoldKey,
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: 48,
      drawer: _CategoryDrawer(
        categories: ['Ultimi Aggiunti', ...groups.map((g) => g.label)],
        selected: _selectedCategory,
        onSelected: (category) {
          setState(() => _selectedCategory =
              category == 'Ultimi Aggiunti' ? null : category);
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
                      prefixIcon:
                          const Icon(Icons.search_rounded, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Categorie',
                  icon: const Icon(Icons.category_outlined),
                  onPressed: () =>
                      _scaffoldKey.currentState?.openDrawer(),
                ),
              ],
            ),
          ),
          Expanded(
            child: _query.isNotEmpty
                ? _buildSearchResults(app)
                : visibleGroup != null
                    ? _buildGroupGrid(app, visibleGroup)
                    : _buildRecentGrid(app),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentGrid(AppProvider app) {
    final entries = app.recentEntries(widget.type);
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
      gridDelegate: channelGridDelegate(widget.type,
          maxExtent: ui.gridMaxExtent, compact: ui.compact),
      itemCount: entries.length,
      itemBuilder: (context, i) =>
          _entryCard(app, entries[i]),
    );
  }

  Widget _buildGroupGrid(AppProvider app, CatalogGroup group) {
    final ui = context.watch<UiSettings>();
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: channelGridDelegate(widget.type,
          maxExtent: ui.gridMaxExtent, compact: ui.compact),
      itemCount: group.entries.length,
      itemBuilder: (context, i) => _entryCard(app, group.entries[i]),
    );
  }

  Widget _buildSearchResults(AppProvider app) {
    final q = _query.toLowerCase();
    final matches = <CatalogEntry>[];
    final seen = <String>{};
    for (final g in app.groupedCatalog(widget.type)) {
      for (final e in g.entries) {
        if (!e.primary.name.toLowerCase().contains(q)) continue;
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
      gridDelegate: channelGridDelegate(widget.type,
          maxExtent: ui.gridMaxExtent, compact: ui.compact),
      itemCount: matches.length,
      itemBuilder: (context, i) => _entryCard(app, matches[i]),
    );
  }

  Widget _entryCard(AppProvider app, CatalogEntry entry) {
    return CatalogEntryCard(
      entry: entry,
      isFavorite: app.favoriteIds.contains(entry.primary.id),
      onTap: () => _openEntry(context, entry),
      onFavoriteTap: () => app.toggleFavorite(entry.primary),
    );
  }

  Future<void> _openEntry(
      BuildContext context, CatalogEntry entry) async {
    final channel = await pickVariant(context, entry);
    if (channel == null || !context.mounted) return;
    openChannel(context, channel);
  }
}

/// Left-side category panel. Opens with a swipe from the left edge (also on
/// touch devices) or the categories button; on TV remotes, pressing left on
/// the first grid column reaches the edge and opens the drawer.
class _CategoryDrawer extends StatelessWidget {
  final List<String> categories;
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
              child: Text('Categorie',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final c in categories)
                    ListTile(
                      selected: (selected ?? 'Ultimi Aggiunti') == c,
                      selectedTileColor:
                          AppColors.primary.withValues(alpha: 0.15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      title: Text(
                        c,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: (selected ?? 'Ultimi Aggiunti') == c
                              ? AppColors.primary
                              : AppColors.textPrimary,
                          fontWeight:
                              (selected ?? 'Ultimi Aggiunti') == c
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                        ),
                      ),
                      onTap: () {
                        onSelected(c);
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
