import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/device_type_service.dart';

/// TV: Up/Down inside a Wrap of buttons/chips with uneven widths move to the
/// nearest item of the adjacent row (by horizontal centre). Geometric
/// traversal used to miss misaligned items and jump out of the group. When no
/// row exists in that direction the key is left to the normal traversal, so
/// the remote still leaves the group naturally. Touch: no effect.
class TvWrapNavigation extends StatefulWidget {
  const TvWrapNavigation({super.key, required this.child});
  final Widget child;

  /// Pure choice shared with tests: index of the target rect, or null.
  static int? pick(Rect current, List<Rect> candidates, bool down) {
    int? best;
    double? rowEdge;
    double bestDx = double.infinity;
    for (var i = 0; i < candidates.length; i++) {
      final r = candidates[i];
      final inDirection = down
          ? r.top >= current.bottom - 2
          : r.bottom <= current.top + 2;
      if (!inDirection) continue;
      final edge = down ? r.top : r.bottom;
      final closerRow =
          rowEdge == null || (down ? edge < rowEdge - 4 : edge > rowEdge + 4);
      final sameRow = rowEdge != null && (edge - rowEdge).abs() <= 4;
      final dx = (r.center.dx - current.center.dx).abs();
      if (closerRow) {
        rowEdge = edge;
        best = i;
        bestDx = dx;
      } else if (sameRow && dx < bestDx) {
        best = i;
        bestDx = dx;
      }
    }
    return best;
  }

  @override
  State<TvWrapNavigation> createState() => _TvWrapNavigationState();
}

class _TvWrapNavigationState extends State<TvWrapNavigation> {
  final _node = FocusNode(canRequestFocus: false, skipTraversal: true);

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final down = key == LogicalKeyboardKey.arrowDown;
    if (!down && key != LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || primary.context == null) {
      return KeyEventResult.ignored;
    }
    final nodes = _node.traversalDescendants
        .where(
          (n) =>
              n != primary &&
              n.canRequestFocus &&
              !n.skipTraversal &&
              n.context != null,
        )
        .toList();
    final target = TvWrapNavigation.pick(primary.rect, [
      for (final n in nodes) n.rect,
    ], down);
    if (target == null) return KeyEventResult.ignored;
    nodes[target].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (!DeviceTypeService.isTv) return widget.child;
    return Focus(focusNode: _node, onKeyEvent: _onKey, child: widget.child);
  }
}
