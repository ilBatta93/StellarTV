import 'package:flutter/widgets.dart';

/// Home-only dimensions; catalog and touch presentation keep their defaults.
class TvHomeLayout extends InheritedWidget {
  const TvHomeLayout({
    super.key,
    required this.rowHeight,
    required this.captionHeight,
    this.showTitles = true,
    required super.child,
  });

  final double rowHeight;
  final double captionHeight;
  final bool showTitles;
  static TvHomeLayout? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvHomeLayout>();

  double get carouselHeight => (rowHeight - 12 - 64).clamp(100.0, rowHeight);
  double get posterHeight =>
      (showTitles
              ? carouselHeight - 16 - 17 - captionHeight - 10
              : carouselHeight - 16 - 10)
          .clamp(72.0, 400.0);
  double get posterWidth => posterHeight * 2 / 3;
  double get historyWidth =>
      (carouselHeight - 16 - 8 - captionHeight * 2 / 3 - 10).clamp(
        72.0,
        260.0,
      ) *
      16 /
      9;
  double get rankedHeight => (rowHeight - 12 - 72 - 16).clamp(80.0, 400.0);

  @override
  bool updateShouldNotify(TvHomeLayout oldWidget) =>
      rowHeight != oldWidget.rowHeight ||
      captionHeight != oldWidget.captionHeight ||
      showTitles != oldWidget.showTitles;
}
