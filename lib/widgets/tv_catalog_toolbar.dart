import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/channel.dart';
import '../providers/ui_settings.dart';
import '../services/catalog_rating_service.dart';
import 'tv_focusable.dart';
import '../theme/app_theme.dart';
import 'tv_text_field.dart';

/// Date means the provider's addition date, not the theatrical release date.
enum CatalogSort {
  provider('Predefinito'),
  nameAsc('A–Z'),
  nameDesc('Z–A'),
  dateAsc('Primo aggiunto'),
  dateDesc('Ultimo aggiunto'),
  rating('Voto');

  const CatalogSort(this.label);
  final String label;
}

List<T> sortCatalog<T>(
  Iterable<T> items,
  CatalogSort? order,
  Channel Function(T) channel, {
  double? Function(Channel)? ratingOf,
}) {
  final list = items.toList();
  if (order == null || order == CatalogSort.provider) return list;
  final names = <String, String>{};
  String name(Channel c) =>
      names.putIfAbsent(c.id, () => c.displaySeriesName.toLowerCase());
  final ratings = <String, double>{};
  double rating(Channel c) => ratings.putIfAbsent(
    c.id,
    () => ratingOf?.call(c) ?? CatalogRatingService.instance.ratingOf(c) ?? 0,
  );
  list.sort((a, b) {
    final ca = channel(a), cb = channel(b);
    final alpha = name(ca).compareTo(name(cb));
    final value = switch (order) {
      CatalogSort.provider => 0,
      CatalogSort.nameAsc => alpha,
      CatalogSort.nameDesc => -alpha,
      CatalogSort.dateAsc =>
        ca.addedAt == 0 || cb.addedAt == 0
            ? (ca.addedAt == 0 ? 1 : -1)
            : ca.addedAt.compareTo(cb.addedAt),
      CatalogSort.dateDesc => cb.addedAt.compareTo(ca.addedAt),
      CatalogSort.rating => rating(cb).compareTo(rating(ca)),
    };
    if (ca.addedAt == 0 && cb.addedAt == 0 && order == CatalogSort.dateAsc) {
      return alpha;
    }
    return value != 0 ? value : (alpha != 0 ? alpha : ca.id.compareTo(cb.id));
  });
  return list;
}

class TvCatalogToolbar extends StatefulWidget {
  const TvCatalogToolbar({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onSort,
    required this.sort,
    this.scaffoldKey,
    this.allowRating = true,
    this.trailing,
    this.category,
    this.filters,
    this.platforms,
    this.platformActive = false,
    this.genresOnly = false,
    this.filterActive = false,
    this.activeFilters = const [],
    this.viewMode,
    this.onViewMode,
  });
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final ValueChanged<CatalogSort> onSort;
  final CatalogSort? sort;
  final GlobalKey<ScaffoldState>? scaffoldKey;
  final bool allowRating;
  final Widget? trailing;
  final String? category;
  final WidgetBuilder? filters;

  /// Streaming platform panel (Film / Serie TV); opens in the same space.
  final WidgetBuilder? platforms;
  final bool platformActive;
  final bool genresOnly;

  /// Genre/category filter applied: the filter icon stays orange.
  final bool filterActive;

  /// Labels of applied genre/platform filters, shown as pills next to the
  /// category title while no panel or search field is open.
  final List<String> activeFilters;

  /// Poster layout picker (grid / compact / list); null hides the button.
  final CatalogViewMode? viewMode;
  final ValueChanged<CatalogViewMode>? onViewMode;

  /// Shared by key events and Android system Back (Home owns the route).
  static bool handleBack(FocusNode? focus) {
    final state = focus?.context
        ?.findAncestorStateOfType<_TvCatalogToolbarState>();
    return state?._back() ?? false;
  }

  @override
  State<TvCatalogToolbar> createState() => _TvCatalogToolbarState();
}

class _TvCatalogToolbarState extends State<TvCatalogToolbar> {
  bool _expanded = false;
  bool _filtersOpen = false;
  bool _platformsOpen = false;
  final _filterButton = FocusNode(debugLabel: 'catalogFilters');
  final _platformButton = FocusNode(debugLabel: 'catalogPlatforms');
  final _panel = FocusScopeNode(debugLabel: 'catalog panel');
  final _field = FocusNode();
  final _search = FocusNode(debugLabel: 'catalogSearch');
  final _sort = FocusNode();
  final _view = FocusNode(debugLabel: 'catalogViewMode');
  @override
  void dispose() {
    _filterButton.dispose();
    _platformButton.dispose();
    _panel.dispose();
    _field.dispose();
    _search.dispose();
    _sort.dispose();
    _view.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_expanded) {
      _collapse();
      _search.requestFocus();
      return;
    }
    setState(() {
      _filtersOpen = false;
      _platformsOpen = false;
      _expanded = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) TvTextField.focusWithKeyboard(_field);
    });
  }

  void _collapse() {
    if (!_expanded) return;
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    setState(() => _expanded = false);
  }

  bool _back() {
    if (_expanded) {
      if (TvTextField.dismissKeyboard(_field)) return true;
      _collapse();
      _search.requestFocus();
      return true;
    }
    if (_filtersOpen) {
      _toggleFilters();
      return true;
    }
    if (_platformsOpen) {
      _togglePlatforms();
      return true;
    }
    return false;
  }

  void _focusPanel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !(_filtersOpen || _platformsOpen)) return;
      final nodes = _panel.traversalDescendants.where(
        (n) => n.canRequestFocus && !n.skipTraversal,
      );
      if (nodes.isNotEmpty) nodes.first.requestFocus();
    });
  }

  void _togglePlatforms() {
    _collapse();
    setState(() {
      _filtersOpen = false;
      _platformsOpen = !_platformsOpen;
    });
    if (_platformsOpen) {
      _focusPanel();
    } else {
      _platformButton.requestFocus();
    }
  }

  void _toggleFilters() {
    _collapse();
    setState(() {
      _platformsOpen = false;
      _filtersOpen = !_filtersOpen;
    });
    if (_filtersOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_filtersOpen) return;
        final nodes = _panel.traversalDescendants.where(
          (n) => n.canRequestFocus && !n.skipTraversal,
        );
        if (nodes.isNotEmpty) nodes.first.requestFocus();
      });
    } else {
      _filterButton.requestFocus();
    }
  }

  Future<void> _choose() async {
    final selected = await showDialog<CatalogSort>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ordina'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final order in CatalogSort.values)
                if (widget.allowRating || order != CatalogSort.rating)
                  TvFocusable(
                    autofocus: order == (widget.sort ?? CatalogSort.provider),
                    focusedScale: 1,
                    onPressed: () => Navigator.pop(ctx, order),
                    child: ListTile(
                      title: Text(order.label),
                      trailing: (widget.sort ?? CatalogSort.provider) == order
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.pop(ctx, order),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (selected != null) widget.onSort(selected);
    _sort.requestFocus();
  }

  Future<void> _chooseView() async {
    final current = widget.viewMode ?? CatalogViewMode.grid;
    final selected = await showDialog<CatalogViewMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disposizione'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in CatalogViewMode.values)
                TvFocusable(
                  autofocus: mode == current,
                  focusedScale: 1,
                  onPressed: () => Navigator.pop(ctx, mode),
                  child: ListTile(
                    leading: Icon(mode.icon),
                    title: Text(mode.label),
                    subtitle: Text(mode.description),
                    trailing: current == mode ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(ctx, mode),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (selected != null) widget.onViewMode?.call(selected);
    _view.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.goBack ||
                event.logicalKey == LogicalKeyboardKey.escape ||
                event.logicalKey == LogicalKeyboardKey.browserBack) &&
            _back()) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (focused) {
        if (!focused && _expanded) _collapse();
        if (!focused && (_filtersOpen || _platformsOpen)) {
          setState(() {
            _filtersOpen = false;
            _platformsOpen = false;
          });
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((_filtersOpen && widget.filters != null) ||
                (_platformsOpen && widget.platforms != null))
              Expanded(
                child: FocusScope(
                  node: _panel,
                  onKeyEvent: (_, event) {
                    if (event is KeyDownEvent &&
                        (event.logicalKey == LogicalKeyboardKey.goBack ||
                            event.logicalKey == LogicalKeyboardKey.escape ||
                            event.logicalKey ==
                                LogicalKeyboardKey.browserBack)) {
                      _platformsOpen ? _togglePlatforms() : _toggleFilters();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child:
                      (_platformsOpen ? widget.platforms : widget.filters)
                          ?.call(context) ??
                      const SizedBox.shrink(),
                ),
              )
            else if (_expanded)
              Expanded(
                child: TvTextField(
                  controller: widget.controller,
                  focusNode: _field,
                  onChanged: widget.onChanged,
                  clearable: true,
                  onMoveDown: _collapse,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  ),
                ),
              )
            else
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.category ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      for (final label in widget.activeFilters) ...[
                        const SizedBox(width: 8),
                        _FilterPill(label),
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(width: 8),
            TvFocusable(
              focusNode: _search,
              onPressed: _toggle,
              child: IconButton(
                tooltip: _expanded ? 'Chiudi ricerca' : 'Cerca',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: _expanded
                      ? AppColors.primary
                      : AppColors.textPrimary,
                ),
                onPressed: _toggle,
                icon: Icon(
                  _expanded ? Icons.close_rounded : Icons.search_rounded,
                ),
              ),
            ),
            if (widget.filters != null)
              TvFocusable(
                focusNode: _filterButton,
                onPressed: _toggleFilters,
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.surface,
                    foregroundColor: _filtersOpen || widget.filterActive
                        ? AppColors.primary
                        : AppColors.textPrimary,
                  ),
                  tooltip: _filtersOpen
                      ? 'Chiudi filtri'
                      : (widget.genresOnly
                            ? 'Filtri per genere'
                            : 'Filtri e categorie'),
                  onPressed: _toggleFilters,
                  icon: Icon(
                    _filtersOpen
                        ? Icons.close_rounded
                        : (widget.genresOnly
                              ? Icons.style_outlined
                              : Icons.filter_list_rounded),
                  ),
                ),
              ),
            if (widget.platforms != null)
              TvFocusable(
                focusNode: _platformButton,
                onPressed: _togglePlatforms,
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.surface,
                    foregroundColor: _platformsOpen || widget.platformActive
                        ? AppColors.primary
                        : AppColors.textPrimary,
                  ),
                  tooltip: _platformsOpen
                      ? 'Chiudi piattaforme'
                      : 'Piattaforme streaming',
                  onPressed: _togglePlatforms,
                  icon: Icon(
                    _platformsOpen
                        ? Icons.close_rounded
                        : Icons.connected_tv_rounded,
                  ),
                ),
              ),
            if (widget.viewMode != null && widget.onViewMode != null)
              TvFocusable(
                focusNode: _view,
                onPressed: _chooseView,
                child: IconButton(
                  tooltip: 'Disposizione: ${widget.viewMode!.label}',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.surface,
                  ),
                  onPressed: _chooseView,
                  icon: Icon(widget.viewMode!.icon),
                ),
              ),
            TvFocusable(
              focusNode: _sort,
              onPressed: _choose,
              child: IconButton(
                tooltip: 'Ordina: ${widget.sort?.label ?? "Predefinito"}',
                style: IconButton.styleFrom(backgroundColor: AppColors.surface),
                onPressed: _choose,
                icon: const Icon(Icons.sort_rounded),
              ),
            ),
            if (widget.trailing != null)
              widget.trailing ?? const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}

/// Read-only reminder of an applied filter (never focusable).
class _FilterPill extends StatelessWidget {
  const _FilterPill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.6)),
    ),
    child: Text(
      label,
      maxLines: 1,
      style: TextStyle(
        color: AppColors.primary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
