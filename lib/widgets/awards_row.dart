import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/awards.dart';
import '../models/tmdb_item.dart';
import '../providers/app_provider.dart';
import '../services/awards_service.dart';
import '../theme/app_theme.dart';
import 'poster_card.dart';
import 'section_row.dart';
import 'settings_tiles.dart';
import 'tv_focusable.dart';

const _gold = Color(0xFFE5B64A);

/// Home row of Oscar and Emmy nominees: a year and a category picker, the
/// winner first with a trophy. On TV the pickers sit beside the title and
/// are reached with Up from the posters.
class AwardsRow extends StatefulWidget {
  const AwardsRow({
    super.key,
    required this.onOpen,
    this.tv = false,
    this.onFocusItem,
    this.onRevealHeading,
    this.service,
  });

  final ValueChanged<TmdbItem> onOpen;
  final bool tv;
  final ValueChanged<TmdbItem>? onFocusItem;
  final ValueChanged<BuildContext>? onRevealHeading;
  final AwardsService? service;

  @override
  State<AwardsRow> createState() => _AwardsRowState();
}

class _AwardsRowState extends State<AwardsRow> {
  AwardsService get _service => widget.service ?? AwardsService.instance;
  AwardsCatalog _catalog = AwardsCatalog.empty;
  int? _year;
  String? _category;
  List<TmdbItem>? _items;
  Set<String> _winners = const {};
  int _request = 0;

  final _headingKey = GlobalKey();
  final _postersKey = GlobalKey();
  final _yearFocus = TvHomeSelectorNode('awards year');
  final _categoryFocus = TvHomeSelectorNode('awards category')..selected = true;

  @override
  void initState() {
    super.initState();
    _service.catalog().then((catalog) {
      if (!mounted || catalog.isEmpty) return;
      final year = catalog.yearsDesc.first;
      setState(() {
        _catalog = catalog;
        _year = year;
        _category = catalog.categoriesIn(year).firstOrNull?.id;
      });
      _loadItems();
    });
  }

  @override
  void dispose() {
    _yearFocus.dispose();
    _categoryFocus.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    final year = _year, category = _category;
    if (year == null || category == null) return;
    final request = ++_request;
    setState(() => _items = null);
    final nominees = _catalog.nominees(year, category);
    final items = await _service.items(nominees);
    if (!mounted || request != _request) return;
    bool allowed(TmdbItem item) {
      try {
        return context.read<AppProvider>().isTmdbAllowed(item);
      } on ProviderNotFoundException {
        return true;
      }
    }

    setState(() {
      _winners = {
        for (final n in nominees)
          if (n.winner) '${n.movie ? 'movie' : 'tv'}_${n.id}',
      };
      _items = items.where(allowed).toList();
    });
  }

  Future<void> _pickYear() async {
    final year = _year;
    if (year == null) return;
    final chosen = await pickOption<int>(
      context,
      title: 'Anno della cerimonia',
      options: _catalog.yearsDesc,
      current: year,
      label: (y) => '$y',
    );
    if (chosen == null || chosen == year || !mounted) return;
    final categories = _catalog.categoriesIn(chosen);
    setState(() {
      _year = chosen;
      // Keep the category when that year has it (Miniserie, animation…).
      if (!categories.any((c) => c.id == _category)) {
        _category = categories.firstOrNull?.id;
      }
    });
    _loadItems();
  }

  Future<void> _pickCategory() async {
    final year = _year;
    if (year == null) return;
    final categories = _catalog.categoriesIn(year);
    final current = categories.where((c) => c.id == _category).firstOrNull;
    if (current == null) return;
    final chosen = await pickOption<AwardCategory>(
      context,
      title: 'Premio',
      options: categories,
      current: current,
      label: (c) => c.fullLabel,
    );
    if (chosen == null || chosen.id == _category || !mounted) return;
    setState(() => _category = chosen.id);
    _loadItems();
  }

  @override
  Widget build(BuildContext context) {
    final year = _year;
    if (_catalog.isEmpty || year == null) return const SizedBox.shrink();
    final category = _catalog.categories
        .where((c) => c.id == _category)
        .firstOrNull;
    final pickers = [
      _Picker(
        label: '$year',
        icon: Icons.calendar_month_rounded,
        focusNode: widget.tv ? _yearFocus : null,
        onTap: _pickYear,
        onDown: _focusPosters,
      ),
      SizedBox(width: widget.tv ? 12 : 8),
      Flexible(
        child: _Picker(
          label: category?.fullLabel ?? 'Premio',
          icon: Icons.emoji_events_outlined,
          focusNode: widget.tv ? _categoryFocus : null,
          onTap: _pickCategory,
          onDown: _focusPosters,
        ),
      ),
    ];
    final heading = widget.tv
        ? Padding(
            key: _headingKey,
            padding: const EdgeInsets.fromLTRB(32, 16, 32, 8),
            child: Row(
              children: [
                _bar(28),
                const SizedBox(width: 14),
                const Text(
                  'Oscar ed Emmy',
                  style: TextStyle(
                    fontFamily: 'Sora',
                    color: AppColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 24),
                ...pickers,
              ],
            ),
          )
        : Padding(
            key: _headingKey,
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _bar(34),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Oscar ed Emmy',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Text(
                            'Candidati e vincitori anno per anno',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(children: pickers),
              ],
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [heading, _posters(context)],
    );
  }

  Widget _bar(double height) => Container(
    width: widget.tv ? 5 : 4,
    height: height,
    decoration: BoxDecoration(
      color: _gold,
      borderRadius: BorderRadius.circular(3),
    ),
  );

  void _focusPosters() {
    final posters = _postersKey.currentContext;
    if (posters == null) return;
    Focus.of(posters).traversalDescendants
        .where((n) => n.canRequestFocus)
        .firstOrNull
        ?.requestFocus();
  }

  Widget _posters(BuildContext context) {
    final height = tmdbPosterRowHeight(context);
    final items = _items;
    if (items == null) {
      return SizedBox(
        height: height,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
          ),
        ),
      );
    }
    if (items.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: widget.tv ? 32 : 16,
          vertical: 24,
        ),
        child: const Text(
          'Nessun titolo da mostrare per questa scelta.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }
    return Focus(
      key: ValueKey('awards_${_year}_$_category'),
      canRequestFocus: false,
      skipTraversal: true,
      child: Builder(
        builder: (_) => HorizontalRow(
          key: _postersKey,
          height: height,
          spacing: widget.tv ? 16 : 12,
          itemCount: items.length,
          itemBuilder: (context, i) => Focus(
            canRequestFocus: false,
            onKeyEvent: (_, event) {
              if (!widget.tv ||
                  event.logicalKey != LogicalKeyboardKey.arrowUp) {
                return KeyEventResult.ignored;
              }
              if (event is KeyDownEvent || event is KeyRepeatEvent) {
                _categoryFocus.requestFocus();
              }
              return KeyEventResult.handled;
            },
            child: _NomineeCard(
              item: items[i],
              onOpen: widget.onOpen,
              winner: _winners.contains(items[i].key),
              onFocus: widget.onFocusItem == null
                  ? null
                  : () {
                      widget.onFocusItem!(items[i]);
                      final heading = _headingKey.currentContext;
                      if (heading != null) {
                        widget.onRevealHeading?.call(heading);
                      }
                    },
            ),
          ),
        ),
      ),
    );
  }
}

class _NomineeCard extends StatelessWidget {
  const _NomineeCard({
    required this.item,
    required this.winner,
    required this.onOpen,
    this.onFocus,
  });

  final TmdbItem item;
  final ValueChanged<TmdbItem> onOpen;
  final bool winner;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    // The trophy goes under the score, in the poster's own badge column:
    // drawn in the opposite corner it covered the score on narrow posters.
    return TmdbPosterCard(
      item: item,
      onFocus: onFocus,
      onTap: () => onOpen(item),
      badges: [if (winner) const AwardWinnerBadge()],
    );
  }
}

/// Trophy on the winner's poster.
class AwardWinnerBadge extends StatelessWidget {
  const AwardWinnerBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _gold,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.emoji_events_rounded, size: 13, color: Colors.black),
          SizedBox(width: 3),
          Text(
            'Vincitore',
            style: TextStyle(
              color: Colors.black,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.onDown,
    this.focusNode,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onDown;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _gold),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Icon(
            Icons.arrow_drop_down_rounded,
            size: 20,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
    if (focusNode == null) {
      return Pressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: chip,
      );
    }
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event.logicalKey != LogicalKeyboardKey.arrowDown) {
          return KeyEventResult.ignored;
        }
        if (event is KeyDownEvent || event is KeyRepeatEvent) onDown();
        return KeyEventResult.handled;
      },
      child: TvFocusable(
        focusNode: focusNode,
        revealOnFocus: false,
        onPressed: onTap,
        borderRadius: BorderRadius.circular(22),
        child: chip,
      ),
    );
  }
}
