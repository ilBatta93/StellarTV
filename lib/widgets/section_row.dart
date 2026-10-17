import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../services/device_type_service.dart';

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

  const HorizontalRow({
    super.key,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.spacing = 12,
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
          itemBuilder: itemBuilder,
        ),
      ),
    );
  }

  /// Left/Right never leave the row: at the first or last card the focus
  /// stays put instead of jumping to the row below or above.
  static KeyEventResult _keepInRow(FocusNode row, KeyEvent event) {
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
