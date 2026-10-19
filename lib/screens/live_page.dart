import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/epg_program.dart';
import '../player/playback_session.dart';
import '../services/player_settings_service.dart';
import '../services/catalog_builder.dart';
import '../services/recent_live_channels.dart';
import '../services/xtream_service.dart';
import '../services/xtream_catchup.dart';
import '../widgets/player/video_surface.dart';
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
import 'multiview_screen.dart';

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
  static const _watchedLabel = 'Visti di recente';
  bool _defaultApplied = false;
  Timer? _tick;
  Timer? _previewDelay;

  PlaybackSession? _preview;
  Channel? _selectedChannel;
  EpgProgram? _selectedProgram;
  int _previewGeneration = 0;
  Future<void> _releaseQueue = Future<void>.value();
  late final AppProvider _app;

  @override
  void didUpdateWidget(covariant LivePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active)
      _stopPreview();
    else if (!oldWidget.active) {
      final channel = _selectedChannel;
      if (channel != null) _select(channel, _selectedProgram);
    }
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
    if (old != null) {
      unawaited(old.setVolume(0));
      // The session unmounts and releases its player safely even while it
      // is still opening; wait until the decoder and the provider connection
      // are really free before the next preview or the full player starts.
      _releaseQueue = _releaseQueue.then((_) async {
        try {
          old.dispose();
          await old.released;
        } catch (_) {}
      });
      _app.setPlaybackActive(false);
    }
  }

  /// Guide row currently scrolled in time and its first visible programme.
  String? _epgRow;
  int _epgOffset = 0;

  List<EpgProgram> _upcoming(EpgProvider epg, Channel c) => epg
      .programmesFor(c)
      .where((p) => p.endTime.isAfter(DateTime.now()))
      .toList();

  Future<void> _confirmClearRecent() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Svuotare i canali visti di recente?'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Svuota'),
          ),
        ],
      ),
    );
    if (ok == true) await _recentLive.clear();
  }

  Future<void> _confirmRemoveRecent(Channel c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Rimuovere "${c.name}" dai visti di recente?'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );
    if (ok == true) await _recentLive.remove(c.id);
  }

  void _select(Channel channel, [EpgProgram? program]) {
    final same = _selectedChannel?.id == channel.id;
    if (_epgRow != channel.id) {
      _epgRow = channel.id;
      _epgOffset = 0;
    }
    setState(() {
      _selectedChannel = channel;
      _selectedProgram = program;
    });
    if (same && _preview != null) return;
    _stopPreview();
    if (mounted) setState(() {});
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
      await _releaseQueue;
      if (!mounted ||
          gen != _previewGeneration ||
          !widget.active ||
          ModalRoute.of(context)?.isCurrent != true)
        return;
      final session = PlaybackSession(
        url: channel.url,
        isLive: true,
        settings: settings,
        previewMode: true,
        previewFallback: true,
      );
      _app.setPlaybackActive(true);
      setState(() => _preview = session);
      final start = session.start();
      try {
        await start;
      } catch (_) {}
    });
  }

  Future<void> _watch(Channel channel) async {
    _stopPreview();
    setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await _releaseQueue;
    if (mounted && widget.active) playChannel(context, channel);
  }

  List<String> _headerTimes(EpgProvider epg, Channel? selected) {
    final visible = selected == null
        ? const <EpgProgram>[]
        : _upcoming(epg, selected).skip(_epgOffset).take(3).toList();
    return [
      for (var i = 0; i < 3; i++)
        i < visible.length ? _hm(visible[i].startTime) : '',
    ];
  }

  Widget _tvGuide(List<Channel> channels, EpgProvider epg, AppProvider app) {
    final showWatched = _category == _watchedLabel;
    final selected = channels
        .where((c) => c.id == _selectedChannel?.id)
        .firstOrNull;
    final program =
        _selectedProgram ?? (selected == null ? null : epg.nowFor(selected));
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: LayoutBuilder(
        builder: (context, box) {
          final previewWidth = (box.maxWidth * 0.32).clamp(240.0, 380.0);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 8, 10),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 156,
                            child: Text(
                              'Canali',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          for (final title in _headerTimes(epg, selected))
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 6, 8, 16),
                        itemCount: channels.length,
                        separatorBuilder: (_, _) => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 5),
                          child: Divider(height: 1, color: AppColors.border),
                        ),
                        itemBuilder: (context, i) {
                          final c = channels[i];
                          final all = _upcoming(epg, c);
                          final offset = c.id == _epgRow
                              ? _epgOffset.clamp(
                                  0,
                                  all.isEmpty ? 0 : all.length - 1,
                                )
                              : 0;
                          final programs = all.skip(offset).take(3).toList();
                          return TvCatalogItem(
                            index: i,
                            columns: 1,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 148,
                                  child: TvCategoryEdge(
                                    scaffoldKey: _scaffoldKey,
                                    onOpen: _openCategories,
                                    child: TvFocusable(
                                      focusedScale: 1,
                                      onFocusChange: (focus) {
                                        if (focus) _select(c);
                                      },
                                      onPressed: () => _watch(c),
                                      onLongPress: showWatched
                                          ? () => _confirmRemoveRecent(c)
                                          : null,
                                      child: GestureDetector(
                                        onTap: () => _watch(c),
                                        child: Container(
                                          constraints: const BoxConstraints(
                                            minHeight: 92,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: c.id == selected?.id
                                                ? AppColors.primary.withValues(
                                                    alpha: 0.12,
                                                  )
                                                : AppColors.surface,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: c.id == selected?.id
                                                  ? AppColors.primary
                                                        .withValues(alpha: 0.55)
                                                  : AppColors.border,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              if (c.logo.isNotEmpty) ...[
                                                _channelLogo(c, size: 30),
                                                const SizedBox(width: 8),
                                              ],
                                              Expanded(
                                                child: TvPosterTitle(c.name),
                                              ),
                                            ],
                                          ),
                                        ),
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
                                        title: const Text(
                                          'Programmazione non disponibile',
                                        ),
                                        onTap: () => _watch(c),
                                      ),
                                    ),
                                  )
                                else
                                  for (final (slot, p) in programs.indexed)
                                    Expanded(
                                      child: Focus(
                                        canRequestFocus: false,
                                        skipTraversal: true,
                                        onKeyEvent: (node, event) {
                                          if (event is! KeyDownEvent &&
                                              event is! KeyRepeatEvent) {
                                            return KeyEventResult.ignored;
                                          }
                                          final key = event.logicalKey;
                                          if (key ==
                                                  LogicalKeyboardKey
                                                      .arrowRight &&
                                              slot == programs.length - 1 &&
                                              offset + programs.length <
                                                  all.length) {
                                            _epgRow = c.id;
                                            _epgOffset = offset + 1;
                                            _select(c, all[offset + slot + 1]);
                                            return KeyEventResult.handled;
                                          }
                                          if (key ==
                                                  LogicalKeyboardKey
                                                      .arrowLeft &&
                                              slot == 0 &&
                                              offset > 0) {
                                            _epgRow = c.id;
                                            _epgOffset = offset - 1;
                                            _select(c, all[offset - 1]);
                                            return KeyEventResult.handled;
                                          }
                                          return KeyEventResult.ignored;
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          child: TvFocusable(
                                            focusedScale: 1,
                                            onFocusChange: (focus) {
                                              if (focus) _select(c, p);
                                            },
                                            onPressed: () async {
                                              _stopPreview();
                                              setState(() {});
                                              await _releaseQueue;
                                              if (!context.mounted ||
                                                  !widget.active)
                                                return;
                                              showChannelGuide(context, c);
                                            },
                                            child: Container(
                                              height: 92,
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color:
                                                    p.startTime.isBefore(
                                                      DateTime.now(),
                                                    )
                                                    ? AppColors.card
                                                    : AppColors.surface,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: AppColors.border,
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    p.title,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      height: 1.2,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: Text(
                                                      '${_hm(p.startTime)} – ${_hm(p.endTime)}',
                                                      style: const TextStyle(
                                                        color:
                                                            AppColors.textMuted,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 7),
                                                  LinearProgressIndicator(
                                                    value:
                                                        p.startTime.isBefore(
                                                          DateTime.now(),
                                                        )
                                                        ? _progressOf(p)
                                                        : 0,
                                                    minHeight: 2,
                                                    color: AppColors.primary,
                                                    backgroundColor:
                                                        AppColors.border,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: VerticalDivider(width: 1, color: AppColors.border),
              ),
              SizedBox(
                width: previewWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TvCatalogItem(
                      index: 0,
                      columns: 1,
                      entry: false,
                      child: TvFocusable(
                        key: const ValueKey('live-preview-focus'),
                        focusedScale: 1,
                        onPressed: () {
                          if (selected != null) _watch(selected);
                        },
                        child: GestureDetector(
                          onTap: () {
                            if (selected != null) _watch(selected);
                          },
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: _preview == null
                                  ? const ColoredBox(
                                      color: AppColors.surface,
                                      child: Center(
                                        child: Icon(
                                          Icons.live_tv_rounded,
                                          size: 42,
                                        ),
                                      ),
                                    )
                                  : ListenableBuilder(
                                      listenable: _preview ?? app,
                                      builder: (_, _) {
                                        final session = _preview;
                                        if (session == null)
                                          return const SizedBox.expand();
                                        if (session.status ==
                                            SessionStatus.failed) {
                                          return const ColoredBox(
                                            color: AppColors.surface,
                                            child: Center(
                                              child: Text(
                                                'Anteprima non disponibile',
                                              ),
                                            ),
                                          );
                                        }
                                        return Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            VideoSurface(
                                              session: session,
                                              settings: session.settings,
                                            ),
                                            if (session.status ==
                                                    SessionStatus.connecting ||
                                                session.status ==
                                                    SessionStatus.switching)
                                              const Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: AppColors.border),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (selected != null && selected.logo.isNotEmpty) ...[
                          _channelLogo(selected, size: 36),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: TvPosterTitle(selected?.name ?? 'Diretta TV'),
                        ),
                        if (selected != null)
                          TvFocusable(
                            focusedScale: 1,
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
                      ],
                    ),
                    if (program != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        program.title,
                        maxLines: 3,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Text(
                        '${_hm(program.startTime)} – ${_hm(program.endTime)}',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _channelLogo(Channel channel, {required double size}) => SizedBox(
    key: ValueKey('live-logo-${channel.id}-$size'),
    width: size,
    height: size,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: PosterImage(
        url: channel.logo,
        fit: BoxFit.contain,
        fallbackIcon: Icons.live_tv_rounded,
      ),
    ),
  );

  final _recentLive = RecentLiveChannels.instance;
  void _recentChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _app = context.read<AppProvider>();
    _recentLive.addListener(_recentChanged);
    unawaited(_recentLive.load());
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
    _recentLive.removeListener(_recentChanged);
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
        message: 'Nessun contenuto in diretta disponibile.',
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
    final watched = [
      for (final id in _recentLive.ids)
        if (app.channelById(id) case final c?)
          if (c.type == ContentType.live)
            CatalogEntry(primary: c, variants: [c]),
    ];
    final showWatched = _category == _watchedLabel;
    final selected = groups.where((g) => g.label == _category).firstOrNull;
    var channels = showWatched
        ? [for (final e in watched) e.primary]
        : selected != null
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

    if (DeviceTypeService.isTv && !showWatched) {
      channels = sortCatalog(channels, _sort, (c) => c);
    }

    if (_selectedChannel != null &&
        !channels.any((c) => c.id == _selectedChannel?.id)) {
      _stopPreview();
      _selectedChannel = null;
      _selectedProgram = null;
    }
    if (DeviceTypeService.isTv &&
        widget.active &&
        _selectedChannel == null &&
        channels.isNotEmpty) {
      final first = channels.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active && _selectedChannel == null)
          _select(first);
      });
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
                TvFilterOption(
                  _watchedLabel,
                  showWatched,
                  () => setState(() => _category = _watchedLabel),
                ),
                if (showWatched && _recentLive.ids.isNotEmpty)
                  TvFilterOption(
                    'Svuota visti di recente',
                    false,
                    _confirmClearRecent,
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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TvFocusable(
                  onPressed: _openMultiView,
                  child: IconButton(
                    tooltip: 'MultiView',
                    icon: const Icon(Icons.grid_view_rounded),
                    onPressed: _openMultiView,
                  ),
                ),
                TvFocusable(
                  onPressed: _openEpg,
                  child: IconButton(
                    tooltip: 'Guida TV (EPG)',
                    icon: const Icon(Icons.calendar_view_day_rounded),
                    onPressed: _openEpg,
                  ),
                ),
              ],
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
                  tooltip: 'MultiView',
                  icon: const Icon(Icons.grid_view_rounded),
                  onPressed: _openMultiView,
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
                _chip(
                  _watchedLabel,
                  showWatched,
                  () => setState(() => _category = _watchedLabel),
                ),
                if (showWatched && _recentLive.ids.isNotEmpty)
                  _chip('Svuota recenti', false, _confirmClearRecent),
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
                    if (showWatched) {
                      final c = channels[i];
                      return Dismissible(
                        key: ValueKey('recent-${c.id}'),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => _recentLive.remove(c.id),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: AppColors.error,
                          ),
                        ),
                        child: tile,
                      );
                    }
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
          _watchedLabel: watched.length,
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

  Future<void> _openMultiView() async {
    final channel = _selectedChannel;
    _stopPreview();
    setState(() {});
    // Native decoder/connection must be released before the parallel player opens.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await _releaseQueue;
    if (!mounted || !widget.active) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiViewScreen(initialChannel: channel),
      ),
    );
    if (mounted && widget.active && channel != null) _select(channel);
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
          .where(
            (p) =>
                p.endTime.isAfter(now) ||
                XtreamCatchup.available(channel, p, now),
          )
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
                              if (!XtreamCatchup.available(
                                channel,
                                p,
                                DateTime.now(),
                              ))
                                return;
                              final credentials = context
                                  .read<AppProvider>()
                                  .xtreamCredentials;
                              final server = credentials?['server'];
                              final user = credentials?['username'];
                              final password = credentials?['password'];
                              if (server == null ||
                                  user == null ||
                                  password == null)
                                return;
                              try {
                                final info = await XtreamService().accountInfo(
                                  server: server,
                                  username: user,
                                  password: password,
                                );
                                final zone =
                                    (info['server_info'] as Map?)?['timezone']
                                        ?.toString();
                                final archive = zone == null
                                    ? null
                                    : XtreamCatchup.url(
                                        channel.copyWith(
                                          url:
                                              '${server.replaceAll(RegExp(r'/+$'), '')}/live/${Uri.encodeComponent(user)}/${Uri.encodeComponent(password)}/${Uri.parse(channel.url).pathSegments.last}',
                                        ),
                                        p,
                                        now: DateTime.now(),
                                        timezone: zone,
                                      );
                                if (!ctx.mounted || !context.mounted) return;
                                if (archive == null)
                                  throw StateError('Archive unavailable');
                                Navigator.pop(ctx);
                                playChannel(
                                  context,
                                  channel.copyWith(url: archive),
                                  startAt: Duration.zero,
                                  queue: const [],
                                  archivePlayback: true,
                                );
                              } catch (_) {
                                if (ctx.mounted)
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Recupero non disponibile: controlla il supporto archivio del provider.',
                                      ),
                                    ),
                                  );
                              }
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
                                      if (!live &&
                                          XtreamCatchup.available(
                                            channel,
                                            p,
                                            now,
                                          )) ...[
                                        const SizedBox(width: 8),
                                        Icon(
                                          Icons.replay_rounded,
                                          size: 16,
                                          color: AppColors.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Rivedi',
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 12,
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
