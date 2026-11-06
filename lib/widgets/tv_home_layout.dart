import 'package:flutter/widgets.dart';

/// Height of the TV top bar. Pages start below it; the Home artwork extends
/// under it so the translucent bar shows the picture through.
const double kTvTopBarHeight = 60;

/// Size of the TV Home row headings (Sora bold). One value for every row,
/// so headings never compete with the banner logo above them.
const double kTvRowTitleSize = 22;

/// Home-only dimensions; catalog and touch presentation keep their defaults.
///
/// Everything derives from the space left under the banner and from the
/// look-and-feel choices: banner size, titles under covers, and the focus
/// zoom and ring, whose growth is reserved so the selected card is never
/// clipped.
class TvHomeLayout extends InheritedWidget {
  const TvHomeLayout({
    super.key,
    required this.rowHeight,
    required this.captionHeight,
    this.showTitles = true,
    this.focusScale = 1.06,
    this.ringWidth = 2.5,
    required super.child,
  });

  final double rowHeight;
  final double captionHeight;
  final bool showTitles;

  /// "Effetto di selezione" of covers: zoom and ring of the focused card.
  final double focusScale;
  final double ringWidth;

  static TvHomeLayout? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvHomeLayout>();

  /// Title padding (14+8) plus one heading line. The face is taller than
  /// the caption box, so the carousel yields that space instead of
  /// overflowing.
  double get _titleBlock {
    final line = captionHeight * (kTvRowTitleSize / 15) * (1.5 / 1.2);
    return (22 + line).ceilToDouble();
  }

  double get carouselHeight =>
      (rowHeight - 12 - _titleBlock).clamp(100.0, rowHeight);

  /// Tallest card (picture and titles) whose zoomed, ringed frame still
  /// fits the carousel with a small margin.
  double fit(double height) =>
      ((height - 2 * ringWidth - 6) / focusScale).clamp(0.0, height);

  double get cardHeight => fit(carouselHeight);

  double get posterHeight =>
      (showTitles ? cardHeight - 27 - captionHeight : cardHeight - 10).clamp(
        72.0,
        400.0,
      );
  double get posterWidth => posterHeight * 2 / 3;
  double get historyWidth =>
      (cardHeight - 8 - captionHeight * 2 / 3 - 10).clamp(72.0, 260.0) * 16 / 9;
  double get rankedHeight => (rowHeight - 12 - 72 - 16).clamp(80.0, 400.0);

  /// Picture height of a ranked card inside a [rankedHeight] row.
  double get rankedImageHeight => fit(rankedHeight);

  @override
  bool updateShouldNotify(TvHomeLayout oldWidget) =>
      rowHeight != oldWidget.rowHeight ||
      captionHeight != oldWidget.captionHeight ||
      showTitles != oldWidget.showTitles ||
      focusScale != oldWidget.focusScale ||
      ringWidth != oldWidget.ringWidth;
}
