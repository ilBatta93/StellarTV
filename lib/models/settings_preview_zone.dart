import 'dart:ui';

/// Which screen the settings preview draws.
enum PreviewSurface { home, catalog }

/// Part of the screen a setting changes: the preview scrolls to it and
/// lights it up while that setting has the focus or the finger.
enum PreviewZone {
  homePage(PreviewSurface.home, 'Tutta la Home'),
  banner(PreviewSurface.home, 'Banner'),
  recommended(PreviewSurface.home, 'Consigliati e Top'),
  recent(PreviewSurface.home, 'Viste di recente'),
  focus(PreviewSurface.home, 'Locandina selezionata'),
  catalogPage(PreviewSurface.catalog, 'Catalogo Film'),
  catalogSeries(PreviewSurface.catalog, 'Catalogo Serie TV'),
  posterTopLeft(PreviewSurface.catalog, 'Locandine, in alto a sinistra'),
  posterTopRight(PreviewSurface.catalog, 'Locandine, in alto a destra'),
  posterBottom(PreviewSurface.catalog, 'Locandine, in basso');

  const PreviewZone(this.surface, this.label);

  final PreviewSurface surface;
  final String label;

  /// The zone covers the whole screen: nothing is dimmed.
  bool get whole =>
      this == homePage || this == catalogPage || this == catalogSeries;

  /// Badge corner of a [poster] picture this zone points at; null when
  /// the zone is not a corner.
  Rect? cornerOf(Rect poster) => switch (this) {
    posterTopLeft => Rect.fromLTWH(
      poster.left,
      poster.top,
      poster.width * 0.62,
      poster.height * 0.3,
    ),
    posterTopRight => Rect.fromLTRB(
      poster.right - poster.width * 0.38,
      poster.top,
      poster.right,
      poster.top + poster.height * 0.22,
    ),
    posterBottom => Rect.fromLTRB(
      poster.left,
      poster.bottom - poster.height * 0.26,
      poster.right,
      poster.bottom,
    ),
    _ => null,
  };
}

/// Picture part of a catalog card [card]: a portrait cover on top, with
/// the title (if any) under it. Wider cards are all picture.
Rect posterPictureOf(Rect card, {double aspectRatio = 2 / 3}) {
  final height = card.width / aspectRatio;
  return height >= card.height
      ? card
      : Rect.fromLTWH(card.left, card.top, card.width, height);
}
