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

class CatalogNavigationIcon extends StatelessWidget {
  final IconData icon;
  final ContentType type;
  const CatalogNavigationIcon({
    super.key,
    required this.icon,
    required this.type,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 42,
    height: 26,
    child: Stack(
      children: [
        Align(alignment: Alignment.centerLeft, child: Icon(icon)),
        Align(
          alignment: Alignment.topRight,
          child: CatalogStatusIndicator(type: type),
        ),
      ],
    ),
  );
}
