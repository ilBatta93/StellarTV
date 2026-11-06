import 'dart:math' as math;

enum HomePosterShape { portrait, landscape, square }

enum HomeDensity { automatic, spacious, balanced, dense }

enum HomeBannerSize { compact, balanced, large }

/// What the Home banner shows. [automatic] keeps each device's own choice:
/// the TV opens on the last title watched, the phone on the weekly Top 10.
/// The TV banner always follows the focused title, so [none] is phone-only;
/// [top] on the phone is [automatic] itself.
enum HomeBannerSource { automatic, forYou, top, none }

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

  /// Share of the TV Home (below the top bar) taken by the banner. The TV
  /// shows one row under it, so the steps are wide enough to be seen:
  /// Compatto favours big covers, Grande the picture and the plot.
  double get tvFraction => switch (this) {
    HomeBannerSize.compact => 0.36,
    HomeBannerSize.balanced => 0.44,
    HomeBannerSize.large => 0.52,
  };
  String get label => switch (this) {
    HomeBannerSize.compact => 'Compatto',
    HomeBannerSize.balanced => 'Bilanciato',
    HomeBannerSize.large => 'Grande',
  };
}

extension HomeBannerSourceInfo on HomeBannerSource {
  String label({required bool tv}) => switch (this) {
    HomeBannerSource.automatic =>
      tv ? 'Ultima visione' : 'Top 10 della settimana',
    HomeBannerSource.forYou => 'Consigliati per te',
    HomeBannerSource.top => 'Top 10 della settimana',
    HomeBannerSource.none => 'Nessun banner',
  };

  /// Choices offered on this kind of device, without duplicates.
  static List<HomeBannerSource> options({required bool tv}) => tv
      ? const [
          HomeBannerSource.automatic,
          HomeBannerSource.forYou,
          HomeBannerSource.top,
        ]
      : const [
          HomeBannerSource.automatic,
          HomeBannerSource.forYou,
          HomeBannerSource.none,
        ];

  /// A value saved on the other kind of device maps to the nearest choice.
  HomeBannerSource on({required bool tv}) => switch (this) {
    HomeBannerSource.top when !tv => HomeBannerSource.automatic,
    HomeBannerSource.none when tv => HomeBannerSource.automatic,
    _ => this,
  };

  static HomeBannerSource parse(Object? value) =>
      HomeBannerSource.values.asNameMap()[value] ?? HomeBannerSource.automatic;
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

/// Home rows the user can reorder or hide. Ids are stable and neutral: they
/// travel to the cloud with the other look-and-feel preferences.
class HomeRows {
  static const recentSeries = 'recent_series';
  static const recentMovies = 'recent_movies';
  static const forYouMovies = 'for_you_movies';
  static const forYouSeries = 'for_you_series';
  static const topWeek = 'top_week';
  static const awards = 'awards';
  static String top(String platformName) =>
      'top_${platformName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}';

  /// Default order: the TV opens on what you are watching, series first;
  /// the phone keeps its films-first order.
  static List<String> defaults({
    required bool tv,
    required Iterable<String> platforms,
  }) => [
    if (tv) ...[
      recentSeries,
      recentMovies,
    ] else ...[
      recentMovies,
      recentSeries,
    ],
    forYouMovies,
    forYouSeries,
    topWeek,
    awards,
    for (final p in platforms) top(p),
  ];

  /// Saved ids first, in their order. A row the save does not know (a new
  /// platform, an older save) keeps its default place after its default
  /// predecessor; unknown saved ids are dropped.
  static List<String> arrange(List<String> defaults, List<String> saved) {
    final known = defaults.toSet();
    final result = <String>[];
    for (final id in saved) {
      if (known.contains(id) && !result.contains(id)) result.add(id);
    }
    for (var i = 0; i < defaults.length; i++) {
      final id = defaults[i];
      if (result.contains(id)) continue;
      var at = 0;
      for (var j = i - 1; j >= 0; j--) {
        final before = result.indexOf(defaults[j]);
        if (before >= 0) {
          at = before + 1;
          break;
        }
      }
      result.insert(at, id);
    }
    return result;
  }

  static List<String> visible(List<String> order, Set<String> hidden) => [
    for (final id in order)
      if (!hidden.contains(id)) id,
  ];
}

/// Logo height and plot lines of the TV banner. The logo is what reads from
/// the sofa, so the plot gives way first: the most lines that still leave
/// [comfortableLogo], else the most that leave [minLogo], else none.
/// [height] is the free banner height, [fixed] the meta row, note and
/// buttons, [overviewLineHeight] null when the plot is off.
({double logo, int overviewLines}) tvHeroLayout({
  required double height,
  required double fixed,
  double? overviewLineHeight,
  double minLogo = 40,
  double comfortableLogo = 56,
  double maxLogo = 88,
}) {
  final rest = height - fixed - 6;
  int lines = 0;
  final line = overviewLineHeight;
  if (line != null && line > 0) {
    double logoWith(int n) => rest - (8 + n * line);
    for (final want in [comfortableLogo, minLogo]) {
      final n = [3, 2, 1].where((n) => logoWith(n) >= want).firstOrNull;
      if (n != null) {
        lines = n;
        break;
      }
    }
  }
  final used = lines == 0 ? 0.0 : 8 + lines * (line ?? 0);
  final logo = (rest - used).clamp(0.0, maxLogo).toDouble();
  return (logo: logo, overviewLines: lines);
}
