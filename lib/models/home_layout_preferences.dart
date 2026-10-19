import 'dart:math' as math;

enum HomePosterShape { portrait, landscape, square }

enum HomeDensity { automatic, spacious, balanced, dense }

enum HomeBannerSize { compact, balanced, large }

extension HomePosterShapeInfo on HomePosterShape {
  double get aspectRatio => switch (this) {
    HomePosterShape.portrait => 2 / 3,
    HomePosterShape.landscape => 16 / 9,
    HomePosterShape.square => 1,
  };
  String get label => switch (this) {
    HomePosterShape.portrait => 'Verticale',
    HomePosterShape.landscape => 'Panoramica',
    HomePosterShape.square => 'Quadrata',
  };
}

extension HomeDensityInfo on HomeDensity {
  String get label => switch (this) {
    HomeDensity.automatic => 'Automatica',
    HomeDensity.spacious => 'Grandi · meno locandine',
    HomeDensity.balanced => 'Bilanciate',
    HomeDensity.dense => 'Piccole · più locandine',
  };
  double visibleCards(bool tv) => switch (this) {
    HomeDensity.automatic => 0,
    HomeDensity.spacious => tv ? 4 : 2,
    HomeDensity.balanced => tv ? 5 : 2.5,
    HomeDensity.dense => tv ? 6 : 3,
  };
}

extension HomeBannerSizeInfo on HomeBannerSize {
  double get fraction => switch (this) {
    HomeBannerSize.compact => 0.40,
    HomeBannerSize.balanced => 0.43,
    HomeBannerSize.large => 0.48,
  };
  String get label => switch (this) {
    HomeBannerSize.compact => 'Compatto',
    HomeBannerSize.balanced => 'Bilanciato',
    HomeBannerSize.large => 'Grande',
  };
}

/// Pure bounds shared by rendering, persistence and tests. No catalog fetches.
class HomeLayoutPolicy {
  static const itemLimits = [10, 20, 30, 50];
  static const recommendationLimits = [5, 10, 15, 20];
  static int recommendationLimit(Object? value) =>
      recommendationLimits.contains(value) ? value as int : 10;
  static const uiScales = [90, 100, 110, 115];
  static int itemLimit(Object? value, {int fallback = 20}) =>
      itemLimits.contains(value) ? value as int : fallback;
  static int uiScale(Object? value) =>
      uiScales.contains(value) ? value as int : 100;
  static double cardWidth({
    required double viewportWidth,
    required double maxImageHeight,
    required double aspectRatio,
    required HomeDensity density,
    required bool tv,
    required double automaticWidth,
    double spacing = 20,
    double rankSpace = 0,
  }) {
    final visible = density.visibleCards(tv);
    final available = math.max(1.0, viewportWidth - (tv ? 64 : 32));
    final requested = visible == 0
        ? automaticWidth
        : (available - spacing * (visible - 1)) / visible - rankSpace;
    final bounded = math.max(
      1.0,
      math.min(requested, maxImageHeight * aspectRatio),
    );
    // On short TVs height is the real limit: still make density choices distinct.
    final factor = switch (density) {
      HomeDensity.automatic || HomeDensity.spacious => 1.0,
      HomeDensity.balanced => 0.85,
      HomeDensity.dense => 0.70,
    };
    return bounded * factor;
  }
}
