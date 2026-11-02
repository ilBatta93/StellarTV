import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/catalog_load_state.dart';
import '../models/content_type.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';

/// Fixed-size, passive status: never participates in remote focus traversal.
class CatalogStatusIndicator extends StatelessWidget {
  final ContentType type;
  final Color? foreground;
  const CatalogStatusIndicator({
    super.key,
    required this.type,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.select<AppProvider, CatalogLoadState>(
      (app) => app.catalogState(type),
    );
    return SizedBox(
      width: 14,
      height: 14,
      child: state.phase == CatalogLoadPhase.idle
          ? null
          : ExcludeFocus(
              child: Tooltip(
                message: '${type.label}: ${state.label}',
                child: Semantics(
                  label: '${type.label}: ${state.label}',
                  child: ExcludeSemantics(child: _symbol(context, state)),
                ),
              ),
            ),
    );
  }

  Widget _symbol(BuildContext context, CatalogLoadState state) {
    final color = foreground ?? AppColors.primary;
    if (state.phase == CatalogLoadPhase.loading) {
      return CircularProgressIndicator(
        strokeWidth: 1.7,
        value: MediaQuery.disableAnimationsOf(context) ? 0.7 : null,
        color: color,
      );
    }
    return Icon(
      switch (state.phase) {
        CatalogLoadPhase.ready => Icons.check_circle_outline_rounded,
        CatalogLoadPhase.cached => Icons.cloud_off_rounded,
        CatalogLoadPhase.failed => Icons.error_outline_rounded,
        _ => Icons.schedule_rounded,
      },
      size: 14,
      color: state.phase == CatalogLoadPhase.queued
          ? foreground ?? AppColors.textMuted
          : color,
    );
  }
}

/// Touch tab icon: every tab draws its icon in the same 28 pt box, and the
/// catalog status is a small badge on the icon corner, shown only while the
/// section loads, waits or has a problem (ready stays readable by
/// accessibility without a mark).
class CatalogNavigationIcon extends StatelessWidget {
  final IconData icon;
  final ContentType? type;
  final Color? color;
  const CatalogNavigationIcon({
    super.key,
    required this.icon,
    this.type,
    this.color,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 28,
    height: 28,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Center(child: Icon(icon, size: 25, color: color)),
        if (type != null)
          Positioned(right: -5, top: -3, child: _CatalogBadge(type: type!)),
      ],
    ),
  );
}

class _CatalogBadge extends StatelessWidget {
  final ContentType type;
  const _CatalogBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final state = context.select<AppProvider, CatalogLoadState>(
      (app) => app.catalogState(type),
    );
    final label = '${type.label}: ${state.label}';
    final Widget? mark = switch (state.phase) {
      CatalogLoadPhase.idle || CatalogLoadPhase.ready => null,
      CatalogLoadPhase.loading => CircularProgressIndicator(
        strokeWidth: 1.6,
        value: MediaQuery.disableAnimationsOf(context) ? 0.7 : null,
        color: AppColors.primary,
      ),
      CatalogLoadPhase.failed => const _Dot(AppColors.error),
      CatalogLoadPhase.cached => const _Dot(AppColors.warning),
      _ => const _Dot(AppColors.textMuted),
    };
    return SizedBox(
      width: 12,
      height: 12,
      child: state.phase == CatalogLoadPhase.idle
          ? null
          : ExcludeFocus(
              child: Tooltip(
                message: label,
                child: Semantics(
                  label: label,
                  child: ExcludeSemantics(child: mark ?? const SizedBox()),
                ),
              ),
            ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot(this.color);

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.background, width: 1.5),
      ),
    ),
  );
}
