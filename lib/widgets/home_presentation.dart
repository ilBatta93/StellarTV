import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../models/home_layout_preferences.dart';
import '../providers/ui_settings.dart';
import '../services/device_type_service.dart';
import 'tv_home_layout.dart';

/// Scopes Home preferences, never altering search or catalog poster geometry.
class HomePresentation extends InheritedWidget {
  const HomePresentation({super.key, required super.child});
  static bool contains(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomePresentation>() != null;
  static double width(
    BuildContext context, {
    bool recent = false,
    bool ranked = false,
  }) {
    final ui = context.watch<UiSettings>();
    final tv = DeviceTypeService.isTv;
    final layout = TvHomeLayout.maybeOf(context);
    final shape = recent ? ui.homeRecentShape : ui.homePosterShape;
    final maxHeight = ranked
        ? (layout?.rankedHeight ?? 196) - 16
        : recent
        ? (layout?.carouselHeight ?? 260) -
              16 -
              8 -
              MediaQuery.textScalerOf(context).scale(13) * 2.5 -
              10
        : layout?.posterHeight ?? 180;
    final automatic = recent
        ? (layout?.historyWidth ?? 208) * shape.aspectRatio / (16 / 9)
        : (layout?.posterWidth ?? 120) * shape.aspectRatio / (2 / 3);
    return HomeLayoutPolicy.cardWidth(
      viewportWidth: MediaQuery.sizeOf(context).width,
      maxImageHeight: maxHeight,
      aspectRatio: shape.aspectRatio,
      density: recent ? ui.homeRecentDensity : ui.homePosterDensity,
      tv: tv,
      automaticWidth: ranked
          ? ((layout?.rankedHeight ?? 196) - 16) * shape.aspectRatio
          : automatic,
      spacing: tv ? 20 : 12,
      rankSpace: ranked ? 72 : 0,
    );
  }

  @override
  bool updateShouldNotify(HomePresentation oldWidget) => false;
}
