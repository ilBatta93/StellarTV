import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'tv_focusable.dart';

class TvFilterOption {
  const TvFilterOption(this.label, this.selected, this.onSelected);
  final String label;
  final bool selected;
  final VoidCallback onSelected;
}

/// Remote-first filter grid: equal-width columns and explicit index-based
/// Up/Down moves, so the D-Pad never escapes geometrically into the catalog
/// below (which closed the panel). Up on the first row and Down on the last
/// row stay inside; only Back closes the panel.
class TvFilterPanel extends StatefulWidget {
  const TvFilterPanel({super.key, required this.options});
  final List<TvFilterOption> options;

  /// Column count for a given width, shared with tests.
  static int columnsFor(double width) =>
      (width / 210).floor().clamp(1, 6).toInt();

  /// Target index for a vertical move, or null to stay put.
  static int? verticalTarget(int index, int count, int columns, bool down) {
    if (count <= 0) return null;
    if (down) {
      final next = index + columns;
      if (next < count) return next;
      // Partial last row: drop to the last option when a row exists below.
      final lastRowStart = ((count - 1) ~/ columns) * columns;
      return index < lastRowStart ? count - 1 : null;
    }
    final prev = index - columns;
    return prev >= 0 ? prev : null;
  }

  @override
  State<TvFilterPanel> createState() => _TvFilterPanelState();
}

class _TvFilterPanelState extends State<TvFilterPanel> {
  final List<FocusNode> _nodes = [];
  int _columns = 1;

  void _syncNodes() {
    while (_nodes.length < widget.options.length) {
      _nodes.add(FocusNode());
    }
    while (_nodes.length > widget.options.length) {
      _nodes.removeLast().dispose();
    }
  }

  @override
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final down = key == LogicalKeyboardKey.arrowDown;
    final up = key == LogicalKeyboardKey.arrowUp;
    if (!down && !up) return KeyEventResult.ignored;
    final index = _nodes.indexWhere((n) => n.hasFocus);
    if (index < 0) return KeyEventResult.ignored;
    final target = TvFilterPanel.verticalTarget(
      index,
      _nodes.length,
      _columns,
      down,
    );
    if (target != null) _nodes[target].requestFocus();
    // Always consumed: the focus never leaves the open panel vertically.
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    _syncNodes();
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            final width = constraints.maxWidth - 8;
            _columns = TvFilterPanel.columnsFor(width);
            final itemWidth = (width - spacing * (_columns - 1)) / _columns;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(4),
              child: Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (var i = 0; i < widget.options.length; i++)
                    SizedBox(
                      width: itemWidth,
                      child: _item(widget.options[i], _nodes[i]),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _item(TvFilterOption option, FocusNode node) => TvFocusable(
    focusNode: node,
    focusedScale: 1,
    borderRadius: BorderRadius.circular(8),
    onPressed: option.onSelected,
    child: InkWell(
      onTap: option.onSelected,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: option.selected
              ? AppColors.primary.withValues(alpha: 0.18)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: option.selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          option.label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            height: 1.3,
            fontWeight: option.selected ? FontWeight.w700 : FontWeight.w500,
            color: option.selected ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
      ),
    ),
  );
}
