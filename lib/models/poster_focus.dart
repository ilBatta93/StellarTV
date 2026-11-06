/// TV focus effect of posters and covers ("Effetto di selezione"). Buttons,
/// chips and menus keep the standard effect so they always read clearly.
enum PosterFocusZoom { none, light, normal, wide }

extension PosterFocusZoomInfo on PosterFocusZoom {
  String get label => switch (this) {
    PosterFocusZoom.none => 'Nessuno',
    PosterFocusZoom.light => 'Leggero',
    PosterFocusZoom.normal => 'Normale',
    PosterFocusZoom.wide => 'Ampio',
  };

  double get scale => switch (this) {
    PosterFocusZoom.none => 1,
    PosterFocusZoom.light => 1.03,
    PosterFocusZoom.normal => 1.06,
    PosterFocusZoom.wide => 1.12,
  };

  static PosterFocusZoom parse(Object? value) =>
      PosterFocusZoom.values.asNameMap()[value] ?? PosterFocusZoom.normal;
}

enum PosterFocusRing { thin, thick, none }

extension PosterFocusRingInfo on PosterFocusRing {
  String get label => switch (this) {
    PosterFocusRing.thin => 'Sottile',
    PosterFocusRing.thick => 'Spesso',
    PosterFocusRing.none => 'Nessuno',
  };

  double get width => switch (this) {
    PosterFocusRing.thin => 2.5,
    PosterFocusRing.thick => 4,
    PosterFocusRing.none => 0,
  };

  static PosterFocusRing parse(Object? value) =>
      PosterFocusRing.values.asNameMap()[value] ?? PosterFocusRing.thin;
}

/// Ring width actually drawn: without zoom a ring always stays, so the
/// selected poster can never look like the others.
double posterFocusRingWidth(PosterFocusZoom zoom, PosterFocusRing ring) =>
    zoom == PosterFocusZoom.none && ring == PosterFocusRing.none
    ? PosterFocusRing.thin.width
    : ring.width;
