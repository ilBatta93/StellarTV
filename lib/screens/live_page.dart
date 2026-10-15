import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/epg_program.dart';
import '../player/playback_session.dart';
import '../services/player_settings_service.dart';
import '../widgets/player/video_surface.dart';
import '../navigation/app_routes.dart';
import '../providers/app_provider.dart';
import '../providers/epg_provider.dart';
import '../services/device_type_service.dart';
import '../services/recording_service.dart';
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
  final bool active;
  const LivePage({super.key, this.active = true});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> with WidgetsBindingObserver {
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
  Timer? _previewDelay;

  PlaybackSession? _preview;
  Channel? _selectedChannel;
  EpgProgram? _selectedProgram;
  int _previewGeneration = 0;
  late final AppProvider _app;

  @override
  void didUpdateWidget(covariant LivePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) _stopPreview();
  }

  void _routeChanged() {
    if (_preview != null || _previewDelay?.isActive == true) {
      _stopPreview();
      if (mounted) setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _routeChanged();
  }

  void _stopPreview() {
    _previewGeneration++;
    _previewDelay?.cancel();
    final old = _preview;
    _preview = null;
    old?.dispose();
    if (old != null) _app.setPlaybackActive(false);
  }

  void _select(Channel channel, [EpgProgram? program]) {
    final same = _selectedChannel?.id == channel.id;
    setState(() {
      _selectedChannel = channel;
      _selectedProgram = program;
    });
    if (same && _preview != null) return;
    _stopPreview();
    final gen = _previewGeneration;
    _previewDelay = Timer(const Duration(milliseconds: 800), () async {
      if (!mounted ||
          !widget.active ||
          ModalRoute.of(context)?.isCurrent != true)
        return;
      final settings = await PlayerSettingsService().load(
        scope: PlayerSettingsScope.liveTv,
      );
      if (!mounted ||
          gen != _previewGeneration ||
          !widget.active ||
          ModalRoute.of(context)?.isCurrent != true)
        return;
      if (_app.kidsMode && !_app.isKidsContent(channel)) return;
      final session = PlaybackSession(
        url: channel.url,
        isLive: true,
        settings: settings,
      )..muted = true;
      _app.setPlaybackActive(true);
      setState(() => _preview = session);
      await session.start();
    });
  }

  Future<void> _watch(Channel channel) async {
    _stopPreview();
    setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (mounted && widget.active) playChannel(context, channel);
  }

  Widget _tvGuide(List<Channel> channels, EpgProvider epg, AppProvider app) {
    final selected = channels
        .where((c) => c.id == _selectedChannel?.id)
        .firstOrNull;
    final program =
        _selectedProgram ?? (selected == null ? null : epg.nowFor(selected));
    return Column(
      children: [
        SizedBox(
          height: 202,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected?.name ?? 'Diretta TV',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        program?.title ?? 'Guida programmi',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (program != null)
                        Text(
                          '${_hm(program.startTime)} – ${_hm(program.endTime)}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Text(
                          program?.description ?? '',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      if (selected != null)
                        Row(
                          children: [
                            TvFocusable(
                              onPressed: () => _watch(selected),
                              child: TextButton.icon(
                                onPressed: () => _watch(selected),
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Guarda'),
                              ),
                            ),
                            TvFocusable(
                              onPressed: () => app.toggleFavorite(selected),
                              child: IconButton(
                                tooltip: 'Preferiti',
                                onPressed: () => app.toggleFavorite(selected),
                                icon: Icon(
                                  app.favoriteIds.contains(selected.id)
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                ),
                              ),
                            ),
                            TvFocusable(
                              onPressed: () {
                                _stopPreview();
                                setState(() {});
                                showChannelGuide(context, selected);
                              },
                              child: IconButton(
                                tooltip: 'Guida e registrazioni',
                                icon: const Icon(Icons.calendar_month_rounded),
                                onPressed: () {
                                  _stopPreview();
                                  setState(() {});
                                  showChannelGuide(context, selected);
                                },
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 28),
                SizedBox(
                  width: 310,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _preview == null
                          ? ColoredBox(
                              color: AppColors.surface,
                              child: const Center(
                                child: Icon(Icons.live_tv_rounded, size: 42),
                              ),
                            )
                          : ListenableBuilder(
                              listenable: _preview ?? app,
                              builder: (_, _) {
                                final session = _preview;
                                if (session == null) return const SizedBox();
                                if (session.status == SessionStatus.failed)
                                  return ColoredBox(
                                    color: AppColors.surface,
                                    child: const Center(
                                      child: Text('Anteprima non disponibile'),
                                    ),
                                  );
                                return Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    VideoSurface(
                                      session: session,
                                      settings: session.settings,
                                    ),
                                    if (session.status ==
                                        SessionStatus.connecting)
                                      const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                  ],
                                );
                              },
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
          child: Row(
            children: [
              const SizedBox(width: 200, child: Text('Canali')),
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Text(
                    _hm(DateTime.now().add(Duration(minutes: 30 * i))),
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
            itemCount: channels.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, i) {
              final c = channels[i];
              final programs = epg
                  .programmesFor(c)
                  .where((p) => p.endTime.isAfter(DateTime.now()))
                  .take(3)
                  .toList();
              return Row(
                children: [
                  SizedBox(
                    width: 192,
                    child: TvCategoryEdge(
                      scaffoldKey: _scaffoldKey,
                      onOpen: _openCategories,
                      child: TvFocusable(
                        focusedScale: 1,
                        onFocusChange: (focus) {
                          if (focus) _select(c);
                        },
                        onPressed: () => _watch(c),
                        child: ListTile(
                          dense: true,
                          title: Text(
                            c.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _watch(c),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (programs.isEmpty)
                    Expanded(
                      child: TvFocusable(
                        focusedScale: 1,
                        onFocusChange: (focus) {
                          if (focus) _select(c);
                        },
                        onPressed: () => _watch(c),
                        child: ListTile(
                          title: const Text('Programmazione non disponibile'),
                          onTap: () => _watch(c),
                        ),
                      ),
                    )
                  else
                    for (final p in programs)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: TvFocusable(
                            focusedScale: 1,
                            onFocusChange: (focus) {
                              if (focus) _select(c, p);
                            },
                            onPressed: () {
                              _stopPreview();
                              setState(() {});
                              showChannelGuide(context, c);
                            },
                            child: Container(
                              height: 64,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: p.startTime.isBefore(DateTime.now())
                                    ? AppColors.card
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${_hm(p.startTime)} – ${_hm(p.endTime)}',
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
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

  @override
  void initState() {
    super.initState();
    _app = context.read<AppProvider>();
    WidgetsBinding.instance.addObserver(this);
    OpenRoutesObserver.instance.changes.addListener(_routeChanged);
    // Keep "now on" and progress bars current.
    _tick = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    OpenRoutesObserver.instance.changes.removeListener(_routeChanged);
    _stopPreview();
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

    if (_selectedChannel != null &&
        !channels.any((c) => c.id == _selectedChannel?.id)) {
      _stopPreview();
      _selectedChannel = null;
      _selectedProgram = null;
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
              : DeviceTypeService.isTv
              ? _tvGuide(channels, epg, app)
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

  void _openEpg() {
    _stopPreview();
    setState(() {});
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EpgSettingsScreen()),
    );
  }

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
                    autofocus: DeviceTypeService.isTv,
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
                        // TV: every programme is a focus stop so the remote
                        // can scroll the whole guide; OK on the live one plays.
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TvFocusable(
                            borderRadius: BorderRadius.circular(12),
                            focusedScale: 1.0,
                            onPressed: () async {
                              if (live) {
                                Navigator.pop(ctx);
                                playChannel(context, channel);
                                return;
                              }
                              // Future programme: OK schedules/cancels it.
                              final rec = RecordingService.instance;
                              final messenger = ScaffoldMessenger.maybeOf(ctx);
                              if (!RecordingService.canRecord(channel)) {
                                messenger?.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Questo canale non può essere registrato',
                                    ),
                                  ),
                                );
                                return;
                              }
                              final existing = rec.scheduledFor(
                                channel,
                                p.startTime,
                              );
                              if (existing != null) {
                                await rec.stop(existing.id);
                                messenger?.showSnackBar(
                                  const SnackBar(
                                    content: Text('Registrazione annullata'),
                                  ),
                                );
                              } else {
                                await rec.schedule(
                                  channel,
                                  title: p.title,
                                  start: p.startTime,
                                  end: p.endTime,
                                );
                                messenger?.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Registrazione programmata: ${p.title}. '
                                      'Lascia l\'app aperta durante il programma.',
                                    ),
                                  ),
                                );
                              }
                              (ctx as Element).markNeedsBuild();
                            },
                            child: Container(
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
                                      if (!live &&
                                          RecordingService.instance
                                                  .scheduledFor(
                                                    channel,
                                                    p.startTime,
                                                  ) !=
                                              null) ...[
                                        const SizedBox(width: 8),
                                        const Icon(
                                          Icons.fiber_manual_record_rounded,
                                          color: AppColors.error,
                                          size: 12,
                                        ),
                                        const SizedBox(width: 4),
                                        const Text(
                                          'REGISTRAZIONE PROGRAMMATA',
                                          style: TextStyle(
                                            color: AppColors.error,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
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
                            ),
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
