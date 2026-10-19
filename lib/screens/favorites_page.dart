import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/content_type.dart';
import '../navigation/app_routes.dart';
import '../providers/app_provider.dart';
import '../providers/ui_settings.dart';
import '../theme/app_theme.dart';
import '../services/device_type_service.dart';
import '../widgets/tv_catalog_navigation.dart';
import '../widgets/tv_filter_panel.dart';
import '../widgets/tv_focusable.dart';
import '../widgets/poster_card.dart';
import '../widgets/section_row.dart';
import 'catalog_page.dart';

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final favs = app.favorites;
    final tabs = [
      (ContentType.live, 'Diretta'),
      (ContentType.movie, 'Film'),
      (ContentType.series, 'Serie TV'),
    ];

    return DefaultTabController(
      length: tabs.length + 1,
      child: Builder(
        builder: (context) => catalogColumn(
          children: [
            if (DeviceTypeService.isTv)
              AnimatedBuilder(
                animation: DefaultTabController.of(context),
                builder: (_, _) => TvFilterPanel(
                  options: [
                    for (final (index, label) in [
                      'Diretta',
                      'Film',
                      'Serie TV',
                      'La mia lista',
                    ].indexed)
                      TvFilterOption(
                        label,
                        DefaultTabController.of(context).index == index,
                        () => DefaultTabController.of(context).animateTo(index),
                      ),
                  ],
                ),
              )
            else
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: AppColors.primary,
                labelColor: AppColors.textPrimary,
                unselectedLabelColor: AppColors.textSecondary,
                dividerColor: AppColors.border,
                labelStyle: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                tabs: [
                  const Tab(text: 'Diretta'),
                  const Tab(text: 'Film'),
                  const Tab(text: 'Serie TV'),
                  const Tab(text: 'La mia lista'),
                ],
              ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final (type, label) in tabs)
                    Builder(
                      builder: (context) {
                        final items = favs
                            .where(
                              (c) =>
                                  c.type == type ||
                                  (type == ContentType.series &&
                                      c.type == ContentType.anime),
                            )
                            .toList();
                        if (items.isEmpty) {
                          final tabs = DefaultTabController.of(context);
                          void next() =>
                              tabs.animateTo((tabs.index + 1) % tabs.length);
                          return EmptyState(
                            icon: Icons.favorite_border_rounded,
                            title: 'Nessun preferito in $label',
                            message: 'Tocca il cuore su un contenuto (o tienilo premuto) per salvarlo qui.',
                            action: DeviceTypeService.isTv
                                ? TvFocusable(
                                    // Keeps the remote anchored when the
                                    // last favourite of this tab is removed.
                                    autofocus: true,
                                    focusedScale: 1,
                                    borderRadius: BorderRadius.circular(8),
                                    onPressed: next,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: AppColors.border,
                                        ),
                                      ),
                                      child: const Text('Scheda successiva'),
                                    ),
                                  )
                                : null,
                          );
                        }
                        return ChannelGrid(
                          channels: items,
                          type: type,
                          padding: const EdgeInsets.all(16),
                        );
                      },
                    ),
                  _MyList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = context.watch<AppProvider>().tmdbFavorites;
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.bookmark_border_rounded,
        title: 'La tua lista è vuota',
        message: 'Aggiungi film e serie dalle classifiche e dai consigli per ritrovarli qui.',
      );
    }
    final ui = context.watch<UiSettings>();
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: channelGridDelegate(
        ContentType.movie,
        maxExtent: ui.gridMaxExtent,
        compact: ui.compact,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final card = TmdbPosterCard(
          item: items[i],
          width: double.infinity,
          onTap: () => openTmdbItem(context, items[i]),
        );
        if (!DeviceTypeService.isTv) return card;
        final delegate = channelGridDelegate(
          ContentType.movie,
          maxExtent: ui.gridMaxExtent,
          compact: ui.compact,
        );
        final columns =
            ((MediaQuery.sizeOf(context).width - 32) /
                    (delegate.maxCrossAxisExtent + delegate.crossAxisSpacing))
                .ceil()
                .clamp(1, 100);
        return TvCatalogItem(index: i, columns: columns, child: card);
      },
    );
  }
}
