import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/channel.dart';
import '../models/content_type.dart';
import '../navigation/app_routes.dart';
import '../providers/app_provider.dart';
import '../services/catalog_builder.dart';
import '../theme/app_theme.dart';
import '../widgets/channel_card.dart';
import '../widgets/section_row.dart';
import 'settings_screen.dart';

SliverGridDelegate channelGridDelegate(ContentType type, {double maxExtent = 140}) {
  final isLive = type == ContentType.live;
  return SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: isLive ? 150 : maxExtent,
    childAspectRatio: isLive ? 0.9 : 0.58,
    crossAxisSpacing: 12,
    mainAxisSpacing: 16,
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
              style: const TextStyle(
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
                  style: const TextStyle(
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
    return GridView.builder(
      padding: padding,
      gridDelegate: channelGridDelegate(type),
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
      return const Center(
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

    final q = _query.toLowerCase();
    final filtered = q.isEmpty
        ? groups
        : [
            for (final g in groups)
              CatalogGroup(
                label: g.label,
                entries: [
                  for (final e in g.entries)
                    if (e.primary.name.toLowerCase().contains(q)) e,
                ],
              ),
          ].where((g) => g.entries.isNotEmpty).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Cerca tra $_noun',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'Nessun risultato',
                  message: 'Prova con un altro titolo o categoria.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  itemCount: filtered.length,
                  itemBuilder: (context, gi) {
                    final group = filtered[gi];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  group.label,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              Text(
                                '${group.entries.length}',
                                style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: channelGridDelegate(
                                widget.type,
                                maxExtent: 140),
                            itemCount: group.entries.length,
                            itemBuilder: (context, i) {
                              final entry = group.entries[i];
                              return CatalogEntryCard(
                                entry: entry,
                                isFavorite: app.favoriteIds
                                    .contains(entry.primary.id),
                                onTap: () => _openEntry(context, entry),
                                onFavoriteTap: () =>
                                    app.toggleFavorite(entry.primary),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _openEntry(
      BuildContext context, CatalogEntry entry) async {
    final channel = await pickVariant(context, entry);
    if (channel == null || !context.mounted) return;
    openChannel(context, channel);
  }
}
