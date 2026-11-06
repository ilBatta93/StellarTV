import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/home_layout_preferences.dart';
import '../models/history_entry.dart';
import '../models/poster_focus.dart';
import '../models/settings_preview_zone.dart';
import '../models/tmdb_item.dart';
import '../providers/app_provider.dart';
import '../providers/discover_provider.dart';
import '../providers/history_provider.dart';
import '../providers/ui_settings.dart';
import '../services/catalog_builder.dart';
import '../services/device_type_service.dart';
import '../theme/app_theme.dart';
import '../widgets/catalog_layouts.dart';
import '../widgets/channel_card.dart';
import '../widgets/home_art.dart';
import '../widgets/home_presentation.dart';
import '../widgets/poster_card.dart';
import '../widgets/section_row.dart';
import '../widgets/settings_tiles.dart';
import '../widgets/tv_focusable.dart';
import '../widgets/tv_home_layout.dart';
import 'catalog_page.dart';

/// State of the settings preview: which part of the screen the current
/// setting changes, an option being tried before it is confirmed, and the
/// values the page opened with ("Prima").
class SettingsPreviewController extends ChangeNotifier {
  SettingsPreviewController(this.live) : _before = live.previewCopy() {
    live.addListener(_onLive);
  }

  final UiSettings live;
  final UiSettings _before;
  UiSettings? _trial;
  PreviewZone? _zone;
  PreviewSurface _surface = PreviewSurface.home;
  ContentType _catalogType = ContentType.movie;
  bool _showBefore = false;
  bool _collapsed = false;
  final Set<_PreviewTargetState> _targets = {};

  PreviewZone? get zone => _zone;
  PreviewSurface get surface => _surface;

  /// Film or Serie TV: the catalog layout last pointed at.
  ContentType get catalogType => _catalogType;
  bool get showingBefore => _showBefore;
  bool get trying => _trial != null;
  bool get collapsed => _collapsed;

  /// Something changed since the page opened: "Prima" has a meaning.
  bool get changed => _before.signature != live.signature;

  /// Values the preview draws.
  UiSettings get shown => _showBefore ? _before : _trial ?? live;

  void _onLive() {
    if (!changed) _showBefore = false;
    notifyListeners();
  }

  /// [zone] null: a setting with nothing to show, the screen stays as is.
  void point(PreviewZone? zone) {
    if (zone == _zone) return;
    _zone = zone;
    if (zone != null) {
      _surface = zone.surface;
      if (zone == PreviewZone.catalogSeries) {
        _catalogType = ContentType.series;
      } else if (zone == PreviewZone.catalogPage) {
        _catalogType = ContentType.movie;
      }
    }
    notifyListeners();
  }

  /// Shows an option on a copy of the current values; nothing is saved.
  Future<void> tryOption(Future<void> Function(UiSettings) apply) async {
    final copy = live.previewCopy();
    await apply(copy);
    _trial = copy;
    _showBefore = false;
    notifyListeners();
  }

  void endTrial() {
    if (_trial == null) return;
    _trial = null;
    notifyListeners();
  }

  void showBefore(bool value) {
    final next = value && changed;
    if (next == _showBefore) return;
    _showBefore = next;
    notifyListeners();
  }

  void toggleCollapsed() {
    _collapsed = !_collapsed;
    notifyListeners();
  }

  /// Phone: the setting crossing the line [y] (global) while the list
  /// scrolls becomes the one the preview follows.
  void probe(double y) {
    for (final target in _targets) {
      final box = target.context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (y >= top && y < top + box.size.height) {
        point(target.widget.zone);
        return;
      }
    }
  }

  @override
  void dispose() {
    live.removeListener(_onLive);
    super.dispose();
  }
}

/// Gives the [PreviewTarget]s below the preview they report to.
class SettingsPreviewScope extends InheritedWidget {
  const SettingsPreviewScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final SettingsPreviewController controller;

  static SettingsPreviewController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SettingsPreviewScope>()?.controller;

  @override
  bool updateShouldNotify(SettingsPreviewScope oldWidget) =>
      controller != oldWidget.controller;
}

/// A setting (or a group of them) and the [zone] it changes. Focus, touch
/// or scrolling past it points the preview there. Adds no focus stop.
class PreviewTarget extends StatefulWidget {
  const PreviewTarget({super.key, required this.zone, required this.child});

  final PreviewZone? zone;
  final Widget child;

  @override
  State<PreviewTarget> createState() => _PreviewTargetState();
}

class _PreviewTargetState extends State<PreviewTarget> {
  SettingsPreviewController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = SettingsPreviewScope.maybeOf(context);
    if (next == _controller) return;
    _controller?._targets.remove(this);
    _controller = next?.._targets.add(this);
  }

  @override
  void dispose() {
    _controller?._targets.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (focused) controller.point(widget.zone);
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => controller.point(widget.zone),
        child: widget.child,
      ),
    );
  }
}

/// Settings list with the preview always in view: pinned on top on a
/// phone (the setting crossing its lower edge leads), beside the list on
/// a TV.
class SettingsPreviewLayout extends StatefulWidget {
  const SettingsPreviewLayout({
    super.key,
    required this.controller,
    required this.list,
  });

  final SettingsPreviewController controller;

  /// The scrollable list of settings.
  final Widget list;

  @override
  State<SettingsPreviewLayout> createState() => _SettingsPreviewLayoutState();
}

class _SettingsPreviewLayoutState extends State<SettingsPreviewLayout> {
  final _listKey = GlobalKey();

  bool _probing = false;

  bool _onScroll(ScrollUpdateNotification n) {
    if (n.metrics.axis != Axis.vertical || _probing) return false;
    // The list lays out the new offset in the next frame: probe after it.
    _probing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _probing = false;
      if (!mounted) return;
      final box = _listKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      // A line just under the top edge: what the eye reads first.
      widget.controller.probe(box.localToGlobal(Offset.zero).dy + 56);
    });
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final list = SettingsPreviewScope(
      controller: widget.controller,
      child: KeyedSubtree(key: _listKey, child: widget.list),
    );
    if (DeviceTypeService.isTv) {
      return LayoutBuilder(
        builder: (context, box) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: list),
            SizedBox(
              width: box.maxWidth * 0.46,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 32, 24),
                child: SettingsLivePreview(
                  controller: widget.controller,
                  expand: true,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final height = (MediaQuery.sizeOf(context).height * 0.3).clamp(
      180.0,
      280.0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SettingsLivePreview(
            controller: widget.controller,
            height: height,
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: _onScroll,
            child: list,
          ),
        ),
      ],
    );
  }
}

/// The preview panel: a header (what is shown, "Prima"/"Dopo") and the
/// real Home or catalog drawn with the values being looked at.
class SettingsLivePreview extends StatelessWidget {
  const SettingsLivePreview({
    super.key,
    required this.controller,
    this.height = 240,
    this.expand = false,
  });

  final SettingsPreviewController controller;
  final double height;

  /// TV side pane: the preview takes the whole height.
  final bool expand;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final frame = ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: _PreviewViewport(controller: controller),
        ),
      );
      return Column(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PreviewHeader(controller: controller),
          if (!controller.collapsed)
            expand
                ? Expanded(child: frame)
                : SizedBox(height: height, child: frame),
        ],
      );
    },
  );
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({required this.controller});

  final SettingsPreviewController controller;

  /// Left from "Prima"/"Dopo" goes back to the settings, never to the
  /// categories the settings pane jumps to.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent ||
        event.logicalKey != LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.ignored;
    }
    final current = FocusManager.instance.primaryFocus;
    if (current == null) return KeyEventResult.ignored;
    final group = node.traversalDescendants.toList();
    final index = group.indexOf(current);
    if (index > 0) {
      group[index - 1].requestFocus();
      return KeyEventResult.handled;
    }
    current.focusInDirection(TraversalDirection.left);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tv = DeviceTypeService.isTv;
    final zone = controller.zone;
    final status = controller.trying
        ? 'Prova: confermi con ${tv ? 'OK' : 'Applica'}'
        : controller.showingBefore
        ? 'Com\'era all\'apertura'
        : zone == null || zone.whole
        ? (controller.surface == PreviewSurface.home
              ? 'Home'
              : controller.catalogType == ContentType.series
              ? 'Catalogo Serie TV'
              : 'Catalogo Film')
        : zone.label;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            controller.trying
                ? Icons.science_outlined
                : Icons.visibility_outlined,
            size: tv ? 20 : 18,
            color: controller.trying
                ? AppColors.primary
                : AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Anteprima',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: ' · $status',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: tv ? 16 : 13,
              ),
            ),
          ),
          if (controller.changed && !controller.trying)
            Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _onKey,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HeaderChip(
                    label: 'Prima',
                    selected: controller.showingBefore,
                    onTap: () => controller.showBefore(true),
                  ),
                  const SizedBox(width: 6),
                  _HeaderChip(
                    label: 'Dopo',
                    selected: !controller.showingBefore,
                    onTap: () => controller.showBefore(false),
                  ),
                ],
              ),
            ),
          if (!tv)
            IconButton(
              tooltip: controller.collapsed
                  ? 'Mostra anteprima'
                  : 'Nascondi anteprima',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                controller.collapsed
                    ? Icons.expand_more_rounded
                    : Icons.expand_less_rounded,
              ),
              onPressed: controller.toggleCollapsed,
            ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tv = DeviceTypeService.isTv;
    final chip = Container(
      padding: EdgeInsets.symmetric(horizontal: tv ? 14 : 10, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: tv ? 15 : 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return TvFocusable(
      onPressed: onTap,
      onAccent: selected,
      onFocusChange: (focused) {
        // TV: resting on a choice already shows it.
        if (focused) onTap();
      },
      borderRadius: BorderRadius.circular(20),
      child: GestureDetector(onTap: onTap, child: chip),
    );
  }
}

/// The real Home or catalog laid out at the size of this screen, scaled
/// into the panel. No focus, no touch, no reading aloud: it is a picture.
class _PreviewViewport extends StatefulWidget {
  const _PreviewViewport({required this.controller});

  final SettingsPreviewController controller;

  @override
  State<_PreviewViewport> createState() => _PreviewViewportState();
}

class _PreviewViewportState extends State<_PreviewViewport>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final _contentKey = GlobalKey();
  final _regions = {for (final zone in PreviewZone.values) zone: GlobalKey()};
  final _cards = List.generate(4, (_) => GlobalKey());
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  _PreviewSamples? _samples;
  List<Rect> _highlights = const [];
  PreviewZone? _scrolledTo;
  PreviewSurface? _surface;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _samples ??= _PreviewSamples.of(context);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// After layout: light up the zone and bring it into the panel.
  void _afterLayout(PreviewZone? zone, PreviewSurface surface) {
    if (!mounted) return;
    final content = _contentKey.currentContext?.findRenderObject();
    if (content is! RenderBox || !content.hasSize) return;
    Rect? rectOf(GlobalKey key) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return null;
      return box.localToGlobal(Offset.zero, ancestor: content) & box.size;
    }

    final rects = <Rect>[];
    if (zone != null && !zone.whole) {
      if (zone.cornerOf(Rect.zero) != null) {
        for (final key in _cards) {
          final card = rectOf(key);
          if (card != null) rects.add(zone.cornerOf(posterPictureOf(card))!);
        }
      } else if (zone == PreviewZone.focus) {
        final card = rectOf(_cards.first);
        if (card != null) rects.add(card);
      } else if (rectOf(_regions[zone]!) case final rect?) {
        rects.add(rect);
      }
    }
    final same =
        rects.length == _highlights.length &&
        Iterable.generate(rects.length).every(
          (i) => (rects[i].topLeft - _highlights[i].topLeft).distance < 1,
        );
    if (!same) {
      setState(() => _highlights = rects);
      final animate = widget.controller.live.animations;
      if (rects.isEmpty || !animate) {
        _pulse.stop();
        _pulse.value = 1;
      } else if (!_pulse.isAnimating) {
        _pulse.repeat(reverse: true);
      }
    }
    if (surface != _surface) {
      _surface = surface;
      _scrolledTo = null;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    if (zone == _scrolledTo || !_scroll.hasClients) return;
    _scrolledTo = zone;
    final target = rects.isEmpty
        ? 0.0
        : rects.map((r) => r.top).reduce((a, b) => a < b ? a : b);
    final viewport = _scroll.position.viewportDimension;
    final bottom = rects.isEmpty
        ? 0.0
        : rects.map((r) => r.bottom).reduce((a, b) => a > b ? a : b);
    // Whole zone in view when it fits, its top a little below the edge.
    final offset =
        (bottom - target <= viewport * 0.85
                ? target - (viewport - (bottom - target)) / 3
                : target - 12)
            .clamp(0.0, _scroll.position.maxScrollExtent);
    if ((offset - _scroll.offset).abs() < 1) return;
    if (widget.controller.live.animations) {
      _scroll.animateTo(
        offset,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scroll.jumpTo(offset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final ui = controller.shown;
    final zone = controller.zone;
    final surface = controller.surface;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _afterLayout(zone, surface),
    );
    final mq = MediaQuery.of(context);
    final view = View.of(context);
    // The real screen, not this page's own (already scaled) viewport.
    final screen = view.physicalSize / view.devicePixelRatio;
    final uiScale = ui.uiScalePercent / 100;
    final width = screen.width / uiScale;
    final height = screen.height / uiScale;
    final textBase = mq.textScaler.scale(1) / controller.live.textScaleFactor;
    return LayoutBuilder(
      builder: (context, box) {
        // Phone: a small phone in the panel, so more than two posters
        // and the rows around the change fit in view.
        final shown = DeviceTypeService.isTv
            ? box.maxWidth
            : (box.maxWidth * 0.62).clamp(0.0, box.maxWidth);
        final scale = shown / width;
        final window = box.maxHeight / scale;
        final stage = surface == PreviewSurface.home
            ? _HomeStage(
                samples: _samples!,
                regions: _regions,
                focusKey: _cards.first,
                focused: zone == PreviewZone.focus,
              )
            : _CatalogStage(
                samples: _samples!,
                type: controller.catalogType,
                width: width,
                cards: _cards,
              );
        return ExcludeFocus(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Center(
                child: SizedBox(
                  width: shown,
                  height: box.maxHeight,
                  child: FittedBox(
                    fit: BoxFit.fill,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      height: window,
                      child: MediaQuery(
                        data: mq.copyWith(
                          size: Size(width, height),
                          // Small panel, small decodes.
                          devicePixelRatio: mq.devicePixelRatio * scale,
                          padding: EdgeInsets.zero,
                          viewPadding: EdgeInsets.zero,
                          viewInsets: EdgeInsets.zero,
                          textScaler: TextScaler.linear(
                            textBase * ui.textScaleFactor,
                          ),
                        ),
                        child: ChangeNotifierProvider<UiSettings>.value(
                          value: ui,
                          child: RepaintBoundary(
                            child: SingleChildScrollView(
                              controller: _scroll,
                              physics: const NeverScrollableScrollPhysics(),
                              child: Stack(
                                key: _contentKey,
                                children: [
                                  stage,
                                  Positioned.fill(
                                    child: RepaintBoundary(
                                      child: CustomPaint(
                                        painter: _HighlightPainter(
                                          rects: _highlights,
                                          pulse: _pulse,
                                          scale: scale,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Dims what does not change and rings what does, pulsing gently.
class _HighlightPainter extends CustomPainter {
  _HighlightPainter({
    required this.rects,
    required this.pulse,
    required this.scale,
  }) : super(repaint: pulse);

  final List<Rect> rects;
  final Animation<double> pulse;

  /// Panel scale: the ring keeps the same thickness on screen.
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (rects.isEmpty) return;
    final pad = 6 / scale;
    final shapes = [
      for (final r in rects)
        RRect.fromRectAndRadius(r.inflate(pad), Radius.circular(10 / scale)),
    ];
    final holes = Path();
    for (final shape in shapes) {
      holes.addRRect(shape);
    }
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        holes,
      ),
      Paint()..color = AppColors.overlay.withValues(alpha: 0.55),
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 / scale
      ..color = AppColors.primary.withValues(alpha: 0.55 + 0.45 * pulse.value);
    for (final shape in shapes) {
      canvas.drawRRect(shape, ring);
    }
  }

  @override
  bool shouldRepaint(_HighlightPainter old) =>
      old.rects != rects || old.scale != scale;
}

/// Titles the preview draws: what this device already has (Home rows,
/// history, catalog), so images come from the cache. A sample set shows
/// every badge state at least once: in progress, watched, favorite, new,
/// 4K and Full HD.
class _PreviewSamples {
  _PreviewSamples({
    required this.recommended,
    required this.top,
    required this.recent,
    required this.posters,
    required this.progress,
    required this.favorites,
  });

  final List<TmdbItem> recommended;
  final List<TmdbItem> top;
  final List<_RecentSample> recent;
  final List<(Channel, String?)> posters;
  final Map<String, PosterProgress> progress;
  final Set<String> favorites;

  static T? _read<T>(BuildContext context) {
    try {
      return context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  static TmdbItem _placeholder(int i) => TmdbItem(
    id: -1 - i,
    mediaType: 'movie',
    title: 'Titolo ${i + 1}',
    overview:
        'La trama del titolo in evidenza compare qui, sotto il nome, '
        'quando la trama nel banner è accesa.',
    posterPath: null,
    backdropPath: null,
    voteAverage: 7.4,
    popularity: 0,
    releaseDate: '',
  );

  factory _PreviewSamples.of(BuildContext context) {
    final discover = _read<DiscoverProvider>(context);
    final app = _read<AppProvider>(context);
    final history = _read<HistoryProvider>(context);
    List<TmdbItem> pick(Iterable<List<TmdbItem>> lists) {
      for (final list in lists) {
        if (list.isNotEmpty) return list.take(10).toList();
      }
      return [for (var i = 0; i < 10; i++) _placeholder(i)];
    }

    final recommended = pick([
      discover?.forYou ?? const [],
      discover?.topMovies ?? const [],
      app?.tmdbFavorites ?? const [],
    ]);
    final top = pick([
      discover?.topMovies ?? const [],
      discover?.topSeries ?? const [],
    ]);
    final recent = <_RecentSample>[
      for (final HistoryEntry e
          in history?.continueWatching.take(8) ?? const <HistoryEntry>[])
        _RecentSample(
          title: e.title,
          image: e.posterUrl,
          progress: e.duration.inSeconds <= 0
              ? null
              : e.position.inSeconds / e.duration.inSeconds,
        ),
    ];
    if (recent.isEmpty) {
      const parts = [0.35, 0.7, 0.15, 0.55, 0.85, 0.25];
      for (var i = 0; i < recommended.length && i < parts.length; i++) {
        recent.add(
          _RecentSample(
            title: recommended[i].title,
            image: recommended[i].posterUrl,
            progress: parts[i],
          ),
        );
      }
    }
    // A bounded walk: a catalog may hold tens of thousands of titles.
    final found = <Channel>[];
    final all = app?.allChannels ?? const <Channel>[];
    for (var i = 0; i < all.length && i < 600 && found.length < 12; i++) {
      final c = all[i];
      if (c.type == ContentType.movie &&
          c.logo.isNotEmpty &&
          !found.any((f) => f.name == c.name)) {
        found.add(c);
      }
    }
    // Three TV grid rows: the real titles repeat, each copy with its own
    // id so the sample badges stay on one poster.
    final real = found.length;
    for (var i = real; i < 24; i++) {
      if (real > 0) {
        found.add(found[i % real].copyWith(id: '${found[i % real].id}#$i'));
        continue;
      }
      found.add(
        Channel(
          id: 'preview_$i',
          name: 'Titolo ${i + 1}',
          url: '',
          logo: '',
          group: '',
          type: ContentType.movie,
        ),
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final posters = <(Channel, String?)>[
      for (var i = 0; i < found.length; i++)
        switch (i) {
          0 => (found[i], '4K'),
          1 => (found[i], 'FHD'),
          3 => (found[i].copyWith(addedAt: now), null),
          _ => (found[i], CatalogBuilder.qualityLabel(found[i].name)),
        },
    ];
    return _PreviewSamples(
      recommended: recommended,
      top: top,
      recent: recent,
      posters: posters,
      progress: {
        posters[0].$1.id: const PosterProgress(progress: 0.45, watched: false),
        posters[1].$1.id: const PosterProgress(progress: 1, watched: true),
        posters[4].$1.id: const PosterProgress(progress: 0.2, watched: false),
      },
      favorites: {
        posters[2].$1.id,
        for (final p in posters)
          if (app?.favoriteIds.contains(p.$1.id) ?? false) p.$1.id,
      },
    );
  }
}

class _RecentSample {
  const _RecentSample({required this.title, this.image, this.progress});
  final String title;
  final String? image;
  final double? progress;
}

void _none() {}

/// Banner, Consigliati, Top and Viste di recente as the Home lays them out.
class _HomeStage extends StatelessWidget {
  const _HomeStage({
    required this.samples,
    required this.regions,
    required this.focusKey,
    required this.focused,
  });

  final _PreviewSamples samples;
  final Map<PreviewZone, GlobalKey> regions;

  /// The card that shows the TV focus look.
  final GlobalKey focusKey;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final ui = context.watch<UiSettings>();
    final tv = DeviceTypeService.isTv;
    final size = MediaQuery.sizeOf(context);
    if (!tv) {
      // Heights read the Home scope: build the rows below it.
      return HomePresentation(
        child: Builder(builder: (context) => _content(context, ui, null)),
      );
    }
    // Same split as the TV Home: banner share first, rows below.
    final area = size.height - kTvTopBarHeight;
    final hero = area * ui.homeBannerSize.tvFraction;
    return HomePresentation(
      child: TvHomeLayout(
        rowHeight: area - hero,
        captionHeight: MediaQuery.textScalerOf(context).scale(15) * 1.2,
        showTitles: ui.homeTitles,
        focusScale: ui.animations ? ui.focusZoom.scale : 1,
        ringWidth: posterFocusRingWidth(ui.focusZoom, ui.focusRing),
        child: Builder(
          builder: (context) => _content(context, ui, hero + kTvTopBarHeight),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, UiSettings ui, double? tvHero) {
    final tv = tvHero != null;
    final source = ui.homeBannerSource.on(tv: tv);
    final banner = source == HomeBannerSource.none
        ? const SizedBox(height: 56)
        : tv
        ? SizedBox(height: tvHero, child: _BannerSample(samples))
        : AspectRatio(
            aspectRatio: 4 / (3.4 * ui.homeBannerSize.fraction / 0.43),
            child: _BannerSample(samples),
          );
    final recommended = samples.recommended
        .take(ui.homeRecommendationLimit)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(key: regions[PreviewZone.banner], child: banner),
        KeyedSubtree(
          key: regions[PreviewZone.recommended],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: 'Consigliati per te'),
              HorizontalRow(
                height: tmdbPosterRowHeight(context),
                spacing: tv ? 20 : 12,
                itemCount: recommended.length,
                itemBuilder: (context, i) {
                  final card = TmdbPosterCard(
                    item: recommended[i],
                    onTap: _none,
                  );
                  if (i != 0) return card;
                  return KeyedSubtree(
                    key: focusKey,
                    child: focused ? PreviewFocused(child: card) : card,
                  );
                },
              ),
              const SectionHeader(title: 'Top 10 della settimana'),
              HorizontalRow(
                height: TvHomeLayout.maybeOf(context)?.rankedHeight ?? 196,
                spacing: tv ? 20 : 12,
                itemCount: samples.top.length,
                itemBuilder: (context, i) => RankedPosterCard(
                  item: samples.top[i],
                  rank: i + 1,
                  onTap: _none,
                ),
              ),
            ],
          ),
        ),
        KeyedSubtree(
          key: regions[PreviewZone.recent],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: 'Viste di recente'),
              HorizontalRow(
                // As the Home: the TV carousel height, else the card's own.
                height: tv
                    ? TvHomeLayout.maybeOf(context)?.carouselHeight ??
                          homeRowHeight(context)
                    : homeRowHeight(context),
                spacing: tv ? 20 : 12,
                itemCount: samples.recent.length,
                itemBuilder: (context, i) {
                  final r = samples.recent[i];
                  return HomeLandscapeCard(
                    title: r.title,
                    image: r.image,
                    progress: r.progress,
                    onTap: _none,
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// The banner's picture, title and (if on) plot.
class _BannerSample extends StatelessWidget {
  const _BannerSample(this.samples);

  final _PreviewSamples samples;

  @override
  Widget build(BuildContext context) {
    final item = samples.recommended.first;
    final ui = context.watch<UiSettings>();
    final tv = DeviceTypeService.isTv;
    return Stack(
      fit: StackFit.expand,
      children: [
        PosterImage(url: item.backdropUrl ?? item.posterUrl),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, AppColors.background],
              stops: [0.35, 1],
            ),
          ),
        ),
        Positioned(
          left: tv ? 32 : 16,
          right: tv ? null : 16,
          width: tv ? MediaQuery.sizeOf(context).width * 0.45 : null,
          bottom: tv ? 24 : 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: tv ? 26 : 24,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              if (ui.homeOverview && item.overview.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  item.overview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: tv ? 16 : 13,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The first rows of a catalog in the chosen layout, with the sample
/// posters (see [_PreviewSamples]).
class _CatalogStage extends StatelessWidget {
  const _CatalogStage({
    required this.samples,
    required this.type,
    required this.width,
    required this.cards,
  });

  final _PreviewSamples samples;
  final ContentType type;
  final double width;

  /// The first cards: badge corners are lit on them.
  final List<GlobalKey> cards;

  CatalogEntry _entry(Channel c) => CatalogEntry(primary: c, variants: [c]);

  Widget _keyed(int i, Widget card) =>
      i < cards.length ? KeyedSubtree(key: cards[i], child: card) : card;

  @override
  Widget build(BuildContext context) {
    final ui = context.watch<UiSettings>();
    final tv = DeviceTypeService.isTv;
    final mode = ui.viewModeFor(type);
    final posters = samples.posters;
    const padding = EdgeInsets.fromLTRB(16, 8, 16, 24);
    final usable = width - padding.horizontal;
    Widget body;
    switch (mode) {
      case CatalogViewMode.list:
        body = Padding(
          padding: padding,
          child: Column(
            children: [
              for (var i = 0; i < 5; i++)
                _keyed(
                  i,
                  CatalogListTile(
                    entry: _entry(posters[i].$1),
                    isFavorite: samples.favorites.contains(posters[i].$1.id),
                    onTap: _none,
                    onFavoriteTap: _none,
                  ),
                ),
            ],
          ),
        );
      case CatalogViewMode.landscape:
        body = GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: padding,
          gridDelegate: catalogLandscapeDelegate(ui),
          itemCount: 6,
          itemBuilder: (context, i) => _keyed(
            i,
            CatalogLandscapeCard(
              entry: _entry(posters[i].$1),
              isFavorite: samples.favorites.contains(posters[i].$1.id),
              onTap: _none,
              onFavoriteTap: _none,
            ),
          ),
        );
      case _:
        final delegate = catalogGridDelegate(ui, type, width: usable);
        final columns = gridColumnCount(delegate, usable);
        final count = (columns * 3).clamp(1, posters.length);
        body = GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: tvGridPadding(padding, delegate),
          gridDelegate: delegate,
          itemCount: count,
          itemBuilder: (context, i) {
            final (channel, quality) = posters[i];
            return _keyed(
              i,
              ChannelCard(
                channel: channel,
                isFavorite: samples.favorites.contains(channel.id),
                onTap: _none,
                onFavoriteTap: _none,
                qualityLabel: quality,
                bare: mode == CatalogViewMode.wall,
              ),
            );
          },
        );
        if (mode == CatalogViewMode.wall) {
          body = PosterFocusCap(scale: 1, child: body);
        }
    }
    return PosterProgressSample(
      progress: samples.progress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mode == CatalogViewMode.spotlight)
            CatalogSpotlightHeader(entry: _entry(posters.first.$1)),
          body,
          if (mode == CatalogViewMode.wall && tv)
            CatalogWallStrip(entry: _entry(posters.first.$1)),
        ],
      ),
    );
  }
}

/// [pickOption] that tries each option in the preview before saving it.
/// TV: resting on an option shows it, OK saves, Back leaves things as they
/// were; the list opens on the left so the preview stays in view. Phone:
/// a tap shows it, "Applica" saves.
Future<void> pickWithPreview<T>(
  BuildContext context, {
  required SettingsPreviewController? controller,
  required String title,
  required List<T> options,
  required T current,
  required String Function(T) label,
  required Future<void> Function(UiSettings, T) apply,
  String? Function(T)? detail,
}) async {
  final ui = context.read<UiSettings>();
  if (controller == null) {
    final chosen = await pickOption<T>(
      context,
      title: title,
      options: options,
      current: current,
      label: label,
      detail: detail,
    );
    if (chosen != null) await apply(ui, chosen);
    return;
  }
  void show(T option) => controller.tryOption((copy) => apply(copy, option));
  T? chosen;
  try {
    chosen = DeviceTypeService.isTv
        ? await showGeneralDialog<T>(
            context: context,
            barrierDismissible: true,
            barrierLabel: 'Chiudi',
            barrierColor: AppColors.overlay.withValues(alpha: 0.35),
            pageBuilder: (ctx, _, _) => _TvTrialPanel<T>(
              title: title,
              options: options,
              current: current,
              label: label,
              detail: detail,
              onShow: show,
            ),
          )
        : await showModalBottomSheet<T>(
            context: context,
            isScrollControlled: true,
            backgroundColor: AppColors.surface,
            barrierColor: AppColors.overlay.withValues(alpha: 0.2),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (ctx) => _PhoneTrialSheet<T>(
              title: title,
              options: options,
              current: current,
              label: label,
              detail: detail,
              onShow: show,
            ),
          );
  } finally {
    controller.endTrial();
  }
  if (chosen != null && chosen != current) await apply(ui, chosen);
}

class _TvTrialPanel<T> extends StatelessWidget {
  const _TvTrialPanel({
    required this.title,
    required this.options,
    required this.current,
    required this.label,
    required this.detail,
    required this.onShow,
  });

  final String title;
  final List<T> options;
  final T current;
  final String Function(T) label;
  final String? Function(T)? detail;
  final ValueChanged<T> onShow;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: AppColors.surface,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
        child: SizedBox(
          width: (size.width * 0.4).clamp(320.0, 560.0),
          height: size.height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 6),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(28, 0, 28, 12),
                child: Text(
                  'Fermati su una scelta per vederla a destra. '
                  'OK conferma, Indietro annulla.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 15),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    for (final o in options)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: TvFocusable(
                          autofocus: o == current,
                          borderRadius: BorderRadius.circular(12),
                          onFocusChange: (focused) {
                            if (focused) onShow(o);
                          },
                          onPressed: () => Navigator.pop(context, o),
                          child: _OptionRow(
                            text: label(o),
                            detail: detail?.call(o),
                            current: o == current,
                            selected: o == current,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneTrialSheet<T> extends StatefulWidget {
  const _PhoneTrialSheet({
    required this.title,
    required this.options,
    required this.current,
    required this.label,
    required this.detail,
    required this.onShow,
  });

  final String title;
  final List<T> options;
  final T current;
  final String Function(T) label;
  final String? Function(T)? detail;
  final ValueChanged<T> onShow;

  @override
  State<_PhoneTrialSheet<T>> createState() => _PhoneTrialSheetState<T>();
}

class _PhoneTrialSheetState<T> extends State<_PhoneTrialSheet<T>> {
  late T _selected = widget.current;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    // The pinned preview above stays visible.
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.5,
    ),
    child: SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 2),
            child: Text(
              widget.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 6),
            child: Text(
              'Tocca una scelta per vederla nell\'anteprima.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final o in widget.options)
                    InkWell(
                      onTap: () {
                        setState(() => _selected = o);
                        widget.onShow(o);
                      },
                      child: _OptionRow(
                        text: widget.label(o),
                        detail: widget.detail?.call(o),
                        current: o == widget.current,
                        selected: o == _selected,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annulla'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text('Applica'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.text,
    required this.detail,
    required this.current,
    required this.selected,
  });

  final String text;
  final String? detail;

  /// The saved value.
  final bool current;

  /// Phone: the option being shown.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tv = DeviceTypeService.isTv;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: tv ? 16 : 24, vertical: 12),
      child: Row(
        children: [
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            color: selected ? AppColors.primary : AppColors.textMuted,
            size: tv ? 22 : 20,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: tv ? 18 : 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (detail case final d?)
                  Text(
                    d,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: tv ? 15 : 12.5,
                    ),
                  ),
              ],
            ),
          ),
          if (current)
            Text(
              'Attuale',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: tv ? 14 : 12,
              ),
            ),
        ],
      ),
    );
  }
}
