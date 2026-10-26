import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'tv_focusable.dart';

class TvFilterOption {
  const TvFilterOption(
    this.label,
    this.selected,
    this.onSelected, {
    this.brandColor,
  });
  final Color? brandColor;
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

  static int? horizontalTarget(int index, int count, int columns, bool right) {
    if (count <= 0 || columns <= 0 || index < 0 || index >= count) return null;
    final column = index % columns;
    if (right) {
      return column < columns - 1 && index + 1 < count ? index + 1 : null;
    }
    return column > 0 ? index - 1 : null;
  }

  @override
  State<TvFilterPanel> createState() => _TvFilterPanelState();
}

class _TvFilterPanelState extends State<TvFilterPanel> {
  static const _rowExtent = 68.0;
  static const _spacing = 8.0;
  static const _panelHeight = 220.0;

  final Map<int, FocusNode> _nodes = {};
  final ScrollController _scroll = ScrollController();
  int _columns = 1;
  int? _requestedIndex;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _mount(int index, FocusNode node) => _nodes[index] = node;

  void _unmount(int index, FocusNode node) {
    if (_nodes[index] == node) _nodes.remove(index);
  }

  int _focusedIndex() {
    for (final entry in _nodes.entries) {
      if (entry.value.hasFocus) return entry.key;
    }
    return -1;
  }

  void _reveal(int index) {
    if (!_scroll.hasClients || _columns < 1) return;
    const padding = 4.0;
    final top = padding + (index ~/ _columns) * (_rowExtent + _spacing);
    final bottom = top + _rowExtent;
    final position = _scroll.position;
    final origin = position.pixels;
    final view = position.viewportDimension;
    final max = position.maxScrollExtent;
    double? target;
    if (top < origin) {
      target = top;
    } else if (bottom > origin + view) {
      target = bottom - view;
    }
    if (target == null) return;
    _scroll.jumpTo(target.clamp(0.0, max));
  }

  void _focusIndex(int target, [int attempt = 0]) {
    _requestedIndex = target;
    _reveal(target);
    final node = _nodes[target];
    if (node != null) {
      node.requestFocus();
      return;
    }
    if (attempt >= 3) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _requestedIndex != target) return;
      _focusIndex(target, attempt + 1);
    });
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final down = key == LogicalKeyboardKey.arrowDown;
    final up = key == LogicalKeyboardKey.arrowUp;
    final right = key == LogicalKeyboardKey.arrowRight;
    final left = key == LogicalKeyboardKey.arrowLeft;
    if (!down && !up && !right && !left) return KeyEventResult.ignored;
    final requested = _requestedIndex;
    final index = requested != null && _nodes[requested]?.hasFocus == true
        ? requested
        : _focusedIndex();
    if (index < 0) return KeyEventResult.ignored;
    final count = widget.options.length;
    final target = (down || up)
        ? TvFilterPanel.verticalTarget(index, count, _columns, down)
        : TvFilterPanel.horizontalTarget(index, count, _columns, right);
    if (target != null) _focusIndex(target);
    // Always consumed: the focus never leaves the open panel vertically.
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final requested = _requestedIndex;
    if (requested != null && requested >= widget.options.length) {
      _requestedIndex = null;
    }
    if (widget.options.isEmpty) return const SizedBox.shrink();
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.max(0.0, constraints.maxWidth - 8);
          _columns = TvFilterPanel.columnsFor(width);
          final rows =
              (widget.options.length + _columns - 1) ~/ _columns;
          final content =
              8 + rows * _rowExtent + math.max(0, rows - 1) * _spacing;
          final cap = constraints.maxHeight.isFinite
              ? math.min(constraints.maxHeight, _panelHeight)
              : _panelHeight;
          return SizedBox(
            height: math.min(cap, content),
            child: GridView.builder(
              controller: _scroll,
              primary: false,
              padding: const EdgeInsets.all(4),
              scrollCacheExtent: const ScrollCacheExtent.pixels(
                _rowExtent + _spacing,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _columns,
                mainAxisExtent: _rowExtent,
                crossAxisSpacing: _spacing,
                mainAxisSpacing: _spacing,
              ),
              itemCount: widget.options.length,
              itemBuilder: (context, i) => _FilterCell(
                key: ValueKey(i),
                index: i,
                option: widget.options[i],
                onMount: _mount,
                onUnmount: _unmount,
                onFocused: (index) => _requestedIndex = index,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilterCell extends StatefulWidget {
  const _FilterCell({
    super.key,
    required this.index,
    required this.option,
    required this.onMount,
    required this.onUnmount,
    required this.onFocused,
  });

  final int index;
  final TvFilterOption option;
  final void Function(int index, FocusNode node) onMount;
  final void Function(int index, FocusNode node) onUnmount;
  final ValueChanged<int> onFocused;

  @override
  State<_FilterCell> createState() => _FilterCellState();
}

class _FilterCellState extends State<_FilterCell> {
  final FocusNode _node = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.onMount(widget.index, _node);
  }

  @override
  void didUpdateWidget(_FilterCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      widget.onUnmount(oldWidget.index, _node);
      widget.onMount(widget.index, _node);
    }
  }

  @override
  void dispose() {
    widget.onUnmount(widget.index, _node);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FilterTile(
    option: widget.option,
    node: _node,
    onFocused: () => widget.onFocused(widget.index),
  );
}

class _FilterTile extends StatelessWidget {
  const _FilterTile({
    required this.option,
    required this.node,
    required this.onFocused,
  });

  final TvFilterOption option;
  final FocusNode node;
  final VoidCallback onFocused;

  @override
  Widget build(BuildContext context) => TvFocusable(
    focusNode: node,
    onFocusChange: (focused) {
      if (focused) onFocused();
    },
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
              ? (option.brandColor ?? AppColors.primary).withValues(alpha: 0.18)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                option.brandColor ??
                (option.selected ? AppColors.primary : AppColors.border),
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
