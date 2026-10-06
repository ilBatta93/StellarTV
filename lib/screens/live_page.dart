import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/epg_program.dart';
import '../navigation/app_routes.dart';
import '../providers/app_provider.dart';
import '../providers/epg_provider.dart';
import '../services/device_type_service.dart';
import '../theme/app_theme.dart';
import '../widgets/poster_card.dart';
import '../widgets/section_row.dart';
import '../widgets/tv_focusable.dart';
import '../widgets/tv_category_panel.dart';
import '../widgets/tv_text_field.dart';
import '../widgets/tv_catalog_toolbar.dart';
import '../widgets/tv_filter_panel.dart';
import '../widgets/tv_catalog_navigation.dart';
import 'epg_settings_screen.dart';

/// "Diretta" tab: channel list with what is on now, a progress bar and what
/// comes next, plus a full guide per channel.
class LivePage extends StatefulWidget {
  const LivePage({super.key});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  final TextEditingController _searchController = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  FocusNode? _drawerReturn;
  void _openCategories() {
    _drawerReturn = FocusManager.instance.primaryFocus;
    _scaffoldKey.currentState?.openDrawer();
  }

  void _drawerChanged(bool opened) {
    if (opened) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _drawerReturn;
      if (target != null && target.context != null) target.requestFocus();
    });
  }

  CatalogSort? _sort = CatalogSort.provider;
  String _query = '';
  String? _category;
  bool _defaultApplied = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Keep "now on" and progress bars current.
    _tick = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final epg = context.watch<EpgProvider>();

    if (app.catalogState(ContentType.live).isPending &&
        !app.catalogState(ContentType.live).hasContent) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    final groups = app.groupedCatalog(ContentType.live);
    if (groups.isEmpty) {
      return const EmptyState(
        icon: Icons.live_tv_rounded,
        title: 'Nessun canale',
        message: 'La tua playlist non contiene canali in diretta.',
      );
    }
    // Default category: "TV Sat" (when the playlist has it).
    if (!_defaultApplied) {
      _defaultApplied = true;
      String n(String s) =>
          s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      _category = groups
          .map((g) => g.label)
          .where((l) => n(l) == 'tvsat')
          .followedBy(
            groups.map((g) => g.label).where((l) => n(l).contains('tvsat')),
          )
          .firstOrNull;
    }
    final selected = groups.where((g) => g.label == _category).firstOrNull;
    var channels = selected != null
        ? [for (final e in selected.entries) e.primary]
        : [
            for (final g in groups)
              for (final e in g.entries) e.primary,
          ];
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      channels = channels
          .where(
            (c) =>
                c.name.toLowerCase().contains(q) ||
                (epg.nowFor(c)?.title.toLowerCase().contains(q) ?? false),
          )
          .toList();
    }

    if (DeviceTypeService.isTv) {
      channels = sortCatalog(channels, _sort, (c) => c);
    }

    final content = catalogColumn(
      children: [
        if (DeviceTypeService.isTv)
          TvCatalogToolbar(
            controller: _searchController,
            hint: 'Cerca canale o programma',
            category: _category ?? 'Tutti',
            onChanged: (v) => setState(() => _query = v),
            sort: _sort,
            allowRating: false,
            filters: (_) => TvFilterPanel(
              options: [
                TvFilterOption(
                  'Tutti',
                  _category == null,
                  () => setState(() => _category = null),
                ),
                for (final group in groups)
                  TvFilterOption(
                    group.label,
                    _category == group.label,
                    () => setState(() => _category = group.label),
                  ),
              ],
            ),
            onSort: (value) => setState(() => _sort = value),
            scaffoldKey: _scaffoldKey,
            trailing: TvFocusable(
              onPressed: _openEpg,
              child: IconButton(
                tooltip: 'Guida TV (EPG)',
                icon: const Icon(Icons.calendar_view_day_rounded),
                onPressed: _openEpg,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: TvTextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                      hintText: 'Cerca canale o programma',
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Guida TV (EPG)',
                  icon: epg.isLoading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : const Icon(Icons.calendar_view_day_rounded),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const EpgSettingsScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (!DeviceTypeService.isTv)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                TvCategoryEdge(
                  scaffoldKey: _scaffoldKey,
                  onOpen: _openCategories,
                  child: _chip(
                    'Tutti',
                    _category == null,
                    () => setState(() => _category = null),
                  ),
                ),
                for (final g in groups)
                  _chip(
                    g.label,
                    _category == g.label,
                    () => setState(() => _category = g.label),
                  ),
              ],
            ),
          ),
        if (!epg.hasData && !epg.isLoading)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              epg.error ?? 'Guida TV non ancora disponibile.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
        Expanded(
          child: channels.isEmpty
              ? const EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'Nessun risultato',
                  message: 'Prova con un altro nome o categoria.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: channels.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final tile = _LiveTile(
                      channel: channels[i],
                      now: epg.nowFor(channels[i]),
                      next: epg.nextFor(channels[i]),
                      isFavorite: app.favoriteIds.contains(channels[i].id),
                      onFavorite: () => app.toggleFavorite(channels[i]),
                      channelWrapper: DeviceTypeService.isTv
                          ? (child) => TvCategoryEdge(
                              scaffoldKey: _scaffoldKey,
                              onOpen: _openCategories,
                              child: child,
                            )
                          : null,
                    );
                    return TvCatalogItem(index: i, columns: 1, child: tile);
                  },
                ),
        ),
      ],
    );
    if (!DeviceTypeService.isTv) return content;
    return Scaffold(
      key: _scaffoldKey,
      onDrawerChanged: _drawerChanged,
      drawer: TvCategoryPanel(
        categories: {
          'Tutti': groups.fold<int>(
            0,
            (count, group) => count + group.entries.length,
          ),
          for (final group in groups) group.label: group.entries.length,
        },
        selected: _category ?? 'Tutti',
        onSelected: (category) =>
            setState(() => _category = category == 'Tutti' ? null : category),
        onClose: () => _scaffoldKey.currentState?.closeDrawer(),
      ),
      body: content,
    );
  }

  void _openEpg() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const EpgSettingsScreen()),
  );

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TvFocusable(
        onPressed: onTap,
        borderRadius: BorderRadius.circular(16),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

double _progressOf(EpgProgram p) {
  final total = p.endTime.difference(p.startTime).inSeconds;
  if (total <= 0) return 0;
  final done = DateTime.now().difference(p.startTime).inSeconds;
  return (done / total).clamp(0.0, 1.0);
}

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class _LiveTile extends StatelessWidget {
  final Channel channel;
  final EpgProgram? now;
  final EpgProgram? next;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final Widget Function(Widget child)? channelWrapper;

  const _LiveTile({
    required this.channel,
    required this.now,
    required this.next,
    required this.isFavorite,
    required this.onFavorite,
    this.channelWrapper,
  });

  @override
  Widget build(BuildContext context) {
    // On TV the heart and guide buttons sit outside the tile so the remote can
    // reach them (Right from the channel); the phone layout is unchanged.
    final tv = DeviceTypeService.isTv;
    final actions = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(
            isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 20,
            color: isFavorite ? AppColors.primary : AppColors.textMuted,
          ),
          onPressed: onFavorite,
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Guida',
          icon: const Icon(
            Icons.view_list_rounded,
            size: 20,
            color: AppColors.textMuted,
          ),
          onPressed: () => showChannelGuide(context, channel),
        ),
      ],
    );
    final tile = Pressable(
      onTap: () => playChannel(context, channel),
      onLongPress: () => showChannelGuide(context, channel),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 48,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: PosterImage(
                url: channel.logo,
                fit: BoxFit.contain,
                fallbackIcon: Icons.live_tv_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (now != null) ...[
                    Text(
                      '${_hm(now!.startTime)}  ${now!.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: _progressOf(now!),
                        minHeight: 3,
                        backgroundColor: AppColors.border,
                        valueColor: AlwaysStoppedAnimation(AppColors.primary),
                      ),
                    ),
                    if (next != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Poi ${_hm(next!.startTime)}  ${next!.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ] else
                    Text(
                      channel.group,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (!tv) actions,
          ],
        ),
      ),
    );
    if (!tv) return tile;
    return Row(
      children: [
        Expanded(child: channelWrapper?.call(tile) ?? tile),
        const SizedBox(width: 8),
        actions,
      ],
    );
  }
}

/// Full guide of a channel in a bottom sheet.
Future<void> showChannelGuide(BuildContext context, Channel channel) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final epg = ctx.watch<EpgProvider>();
      final now = DateTime.now();
      final list = epg
          .programmesFor(channel)
          .where((p) => p.endTime.isAfter(now))
          .toList();
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (ctx, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Guarda'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      playChannel(context, channel);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Nessuna informazione sui programmi per questo canale.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: list.length,
                      itemBuilder: (ctx, i) {
                        final p = list[i];
                        final live = p.isNow;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: live
                                ? AppColors.primary.withValues(alpha: 0.12)
                                : AppColors.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: live
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    p.timeRange,
                                    style: TextStyle(
                                      color: live
                                          ? AppColors.primary
                                          : AppColors.textMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (live) ...[
                                    const SizedBox(width: 8),
                                    const Text(
                                      'IN ONDA',
                                      style: TextStyle(
                                        color: AppColors.error,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                p.title,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (p.description.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  p.description,
                                  maxLines: live ? 4 : 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                              if (live) ...[
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: _progressOf(p),
                                  minHeight: 3,
                                  backgroundColor: AppColors.border,
                                  valueColor: AlwaysStoppedAnimation(
                                    AppColors.primary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}
