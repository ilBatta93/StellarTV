import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../services/device_type_service.dart';
import 'tv_focusable.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final VoidCallback? onSeeAll;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        DeviceTypeService.isTv ? 32 : 16,
        DeviceTypeService.isTv ? 18 : 24,
        DeviceTypeService.isTv ? 24 : 8,
        DeviceTypeService.isTv ? 16 : 12,
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: DeviceTypeService.isTv ? 16 : 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onSeeAll != null)
            TextButton(onPressed: onSeeAll, child: const Text('Vedi tutti')),
        ],
      ),
    );
  }
}

class HorizontalRow extends StatelessWidget {
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double spacing;
  final bool Function(FocusNode)? horizontalFocusFilter;

  const HorizontalRow({
    super.key,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.spacing = 12,
    this.horizontalFocusFilter,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _keepInRow,
        child: ListView.separated(
          // Neighbours are pre-built so Right always finds the next card.
          cacheExtent: DeviceTypeService.isTv ? 1200 : null,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(
            horizontal: DeviceTypeService.isTv ? 32 : 16,
            vertical: DeviceTypeService.isTv ? 8 : 0,
          ),
          itemCount: itemCount,
          separatorBuilder: (_, _) => SizedBox(width: spacing),
          itemBuilder: (context, index) {
            final child = itemBuilder(context, index);
            if (!DeviceTypeService.isTv) return child;
            return Builder(
              builder: (cardContext) => Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onFocusChange: (focused) {
                  if (!focused) return;
                  // Home's banner callback reveals the vertical heading only.
                  // Reveal through this position, not Scrollable.ensureVisible,
                  // so horizontal movement never fights the vertical heading.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!cardContext.mounted) return;
                    final target = cardContext.findRenderObject();
                    final scrollable = Scrollable.maybeOf(cardContext);
                    if (target == null ||
                        !target.attached ||
                        scrollable == null) {
                      return;
                    }
                    // Immediate reveal keeps lazy neighbours built even while
                    // the remote repeats faster than a scroll animation.
                    scrollable.position.ensureVisible(target, alignment: 0.5);
                    // Vertical reveal (e.g. entering "Titoli simili" from
                    // above) only when the card is truly off-screen: the page
                    // is nudged by the exact missing pixels and never while
                    // the remote simply walks sideways through the row.
                    final outer = Scrollable.maybeOf(scrollable.context);
                    if (outer != null &&
                        outer.position.axis == Axis.vertical &&
                        target is RenderBox &&
                        outer.context.findRenderObject() is RenderBox) {
                      final cardBox = target as RenderBox;
                      final pageBox =
                          outer.context.findRenderObject()! as RenderBox;
                      final cardRect =
                          cardBox.localToGlobal(Offset.zero) & cardBox.size;
                      final pageRect =
                          pageBox.localToGlobal(Offset.zero) & pageBox.size;
                      var delta = 0.0;
                      if (cardRect.bottom > pageRect.bottom) {
                        delta = cardRect.bottom - pageRect.bottom;
                      } else if (cardRect.top < pageRect.top) {
                        delta = cardRect.top - pageRect.top;
                      }
                      if (delta != 0) {
                        final position = outer.position;
                        final next = (position.pixels + delta).clamp(
                          position.minScrollExtent,
                          position.maxScrollExtent,
                        ).toDouble();
                        position.jumpTo(next);
                      }
                    }
                  });
                },
                child: HorizontalRowScope(child: child),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Left/Right never leave the row: at the first or last card the focus
  /// stays put instead of jumping to the row below or above.
  KeyEventResult _keepInRow(FocusNode row, KeyEvent event) {
    if (!DeviceTypeService.isTv) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final direction = key == LogicalKeyboardKey.arrowRight
        ? TraversalDirection.right
        : key == LogicalKeyboardKey.arrowLeft
        ? TraversalDirection.left
        : null;
    final current = FocusManager.instance.primaryFocus;
    if (direction == null || current == null || current == row) {
      return KeyEventResult.ignored;
    }
    // requestFocus() applies on the next microtask, so checking the focus
    // after focusInDirection() never saw the jump to the row below. Pick
    // the neighbour among this row's own cards instead; none means the
    // edge was reached and the focus simply stays put.
    final here = current.rect;
    FocusNode? best;
    var bestDx = double.infinity;
    for (final node in row.traversalDescendants) {
      if (node == current || !node.canRequestFocus || node.context == null) {
        continue;
      }
      if (horizontalFocusFilter case final accepts?) {
        if (!accepts(node)) continue;
      }
      final dx = direction == TraversalDirection.right
          ? node.rect.center.dx - here.center.dx
          : here.center.dx - node.rect.center.dx;
      if (dx > 1 && dx < bestDx) {
        bestDx = dx;
        best = node;
      }
    }
    best?.requestFocus();
    return KeyEventResult.handled;
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(36),
              ),
              child: Icon(icon, size: 32, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}
