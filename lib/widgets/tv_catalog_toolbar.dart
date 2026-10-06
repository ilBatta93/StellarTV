import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../services/catalog_rating_service.dart';
import 'tv_focusable.dart';
import 'tv_text_field.dart';

/// Date means the provider's addition date, not the theatrical release date.
enum CatalogSort {
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
  if (order == null) return list;
  final names = <String, String>{};
  String name(Channel c) =>
      names.putIfAbsent(c.id, () => c.displaySeriesName.toLowerCase());
  list.sort((a, b) {
    final ca = channel(a), cb = channel(b);
    final alpha = name(ca).compareTo(name(cb));
    final value = switch (order) {
      CatalogSort.nameAsc => alpha,
      CatalogSort.nameDesc => -alpha,
      CatalogSort.dateAsc =>
        ca.addedAt == 0 || cb.addedAt == 0
            ? (ca.addedAt == 0 ? 1 : -1)
            : ca.addedAt.compareTo(cb.addedAt),
      CatalogSort.dateDesc => cb.addedAt.compareTo(ca.addedAt),
      CatalogSort.rating =>
        (ratingOf?.call(cb) ?? CatalogRatingService.instance.ratingOf(cb) ?? 0)
            .compareTo(
              ratingOf?.call(ca) ??
                  CatalogRatingService.instance.ratingOf(ca) ??
                  0,
            ),
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
    this.allowRating = true,
    this.trailing,
    this.category,
  });
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final ValueChanged<CatalogSort> onSort;
  final CatalogSort? sort;
  final bool allowRating;
  final Widget? trailing;
  final String? category;
  @override
  State<TvCatalogToolbar> createState() => _TvCatalogToolbarState();
}

class _TvCatalogToolbarState extends State<TvCatalogToolbar> {
  bool _expanded = false;
  final _field = FocusNode();
  final _search = FocusNode();
  final _sort = FocusNode();
  @override
  void dispose() {
    _field.dispose();
    _search.dispose();
    _sort.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_expanded) {
      setState(() => _expanded = false);
      _search.requestFocus();
      return;
    }
    setState(() => _expanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) TvTextField.focusWithKeyboard(_field);
    });
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
                    autofocus: order == (widget.sort ?? CatalogSort.nameAsc),
                    focusedScale: 1,
                    onPressed: () => Navigator.pop(ctx, order),
                    child: ListTile(
                      title: Text(order.label),
                      trailing: widget.sort == order
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Row(
      children: [
        if (_expanded)
          Expanded(
            child: TvTextField(
              controller: widget.controller,
              focusNode: _field,
              onChanged: widget.onChanged,
              decoration: InputDecoration(
                hintText: widget.hint,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
              ),
            ),
          )
        else
          Expanded(
            child: Text(
              widget.category ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const SizedBox(width: 8),
        TvFocusable(
          focusNode: _search,
          onPressed: _toggle,
          child: IconButton(
            tooltip: _expanded ? 'Chiudi ricerca' : 'Cerca',
            onPressed: _toggle,
            icon: Icon(_expanded ? Icons.close_rounded : Icons.search_rounded),
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
        if (widget.trailing != null) widget.trailing ?? const SizedBox.shrink(),
      ],
    ),
  );
}
