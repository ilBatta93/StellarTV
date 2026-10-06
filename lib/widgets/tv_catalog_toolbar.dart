import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/channel.dart';
import '../services/catalog_rating_service.dart';
import 'tv_focusable.dart';
import 'tv_text_field.dart';

/// Date means the provider's addition date, not the theatrical release date.
enum CatalogSort {
  provider('Predefinito'),
  nameAsc('A–Z'),
  nameDesc('Z–A'),
  dateAsc('Data crescente'),
  dateDesc('Data decrescente'),
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
    this.genresOnly = false,
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
  final bool genresOnly;

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
  final _filterButton = FocusNode(debugLabel: 'catalogFilters');
  final _panel = FocusScopeNode(debugLabel: 'catalog panel');
  final _field = FocusNode();
  final _search = FocusNode(debugLabel: 'catalogSearch');
  final _sort = FocusNode();
  @override
  void dispose() {
    _filterButton.dispose();
    _panel.dispose();
    _field.dispose();
    _search.dispose();
    _sort.dispose();
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
    return false;
  }

  void _toggleFilters() {
    _collapse();
    setState(() => _filtersOpen = !_filtersOpen);
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
          width: 320,
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
        if (!focused && _filtersOpen) {
          setState(() => _filtersOpen = false);
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_filtersOpen && widget.filters != null)
              Expanded(
                child: FocusScope(
                  node: _panel,
                  onKeyEvent: (_, event) {
                    if (event is KeyDownEvent &&
                        (event.logicalKey == LogicalKeyboardKey.goBack ||
                            event.logicalKey == LogicalKeyboardKey.escape ||
                            event.logicalKey ==
                                LogicalKeyboardKey.browserBack)) {
                      _toggleFilters();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child:
                      widget.filters?.call(context) ?? const SizedBox.shrink(),
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
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.category ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            TvFocusable(
              focusNode: _search,
              onPressed: _toggle,
              child: IconButton(
                tooltip: _expanded ? 'Chiudi ricerca' : 'Cerca',
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
            TvFocusable(
              focusNode: _sort,
              onPressed: _choose,
              child: IconButton(
                tooltip: 'Ordina: ${widget.sort?.label ?? "Predefinito"}',
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
