import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/channel.dart';
import '../models/content_type.dart';
import '../navigation/app_routes.dart';
import '../providers/app_provider.dart';
import '../providers/ui_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/category_tab.dart';
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

enum CatalogSort { newest, az, za }

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
      gridDelegate: channelGridDelegate(type, maxExtent: ui.gridMaxExtent),
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
  String? _group;
  CatalogSort _sort = CatalogSort.newest;

  String get _noun => switch (widget.type) {
        ContentType.live => 'canali',
        ContentType.movie => 'film',
        ContentType.series => 'serie',
        ContentType.anime => 'anime',
      };

  List<Channel> _applySort(List<Channel> items) {
    switch (_sort) {
      case CatalogSort.newest:
        // Playlist order reversed: most recently added first.
        return items.reversed.toList();
      case CatalogSort.az:
        final sorted = [...items]..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return sorted;
      case CatalogSort.za:
        final sorted = [...items]..sort(
            (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        return sorted;
    }
  }

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

    final all = app.catalogOf(widget.type);
    if (all.isEmpty) {
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

    final groups = app.groupsOf(widget.type);
    final q = _query.toLowerCase();
    final filtered = all
        .where((c) =>
            (_group == null || c.group == _group) &&
            (q.isEmpty || c.name.toLowerCase().contains(q)))
        .toList();
    final visible = _applySort(filtered);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Cerca tra ${all.length} $_noun',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<CatalogSort>(
                tooltip: 'Ordina',
                icon: const Icon(Icons.sort_rounded,
                    color: AppColors.textSecondary),
                onSelected: (s) => setState(() => _sort = s),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: CatalogSort.newest,
                    child: Text('Ultimi aggiunti'),
                  ),
                  const PopupMenuItem(
                    value: CatalogSort.az,
                    child: Text('Nome A-Z'),
                  ),
                  const PopupMenuItem(
                    value: CatalogSort.za,
                    child: Text('Nome Z-A'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (groups.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CategoryTab(
              categories: groups,
              selected: _group,
              onSelected: (g) => setState(() => _group = g),
            ),
          ),
        Expanded(
          child: visible.isEmpty
              ? EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'Nessun risultato',
                  message: 'Prova con un altro titolo o categoria.',
                )
              : ChannelGrid(channels: visible, type: widget.type),
        ),
      ],
    );
  }
}
