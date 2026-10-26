/// Device-local rendering limits. Pressure mode lasts until process restart,
/// avoiding a timer that reintroduces images while the user is navigating.
/// Home, Discover and the movie, series and person pages share one backdrop
/// ceiling.
class TvRenderPolicy {
  static int decodeLimit({required bool isTv, required bool memoryPressure}) =>
      isTv ? (memoryPressure ? 640 : 960) : 1280;

  /// Full-screen backdrop decode cap: 1280 px normally, 960 px under pressure.
  static int backdropDecodeLimit({required bool memoryPressure}) =>
      memoryPressure ? 960 : 1280;

  static int homeBackdropDecodeLimit({required bool memoryPressure}) =>
      backdropDecodeLimit(memoryPressure: memoryPressure);

  /// Largest published width that stays inside [backdropDecodeLimit].
  /// Pressure selects 780, so a detail page does not keep w1280 as a floor.
  static int backdropRequestWidth({required bool memoryPressure}) {
    final cap = backdropDecodeLimit(memoryPressure: memoryPressure);
    var chosen = 185;
    for (final width in const [185, 342, 500, 780, 1280]) {
      if (width > cap) break;
      chosen = width;
    }
    return chosen;
  }

  static double rowCacheFraction({required bool memoryPressure}) =>
      memoryPressure ? 0 : 1;
  static bool backdropAllowed({
    required bool isTv,
    required bool memoryPressure,
  }) => !isTv || !memoryPressure;
  static bool startupFade({required bool isTv, required bool animations}) =>
      !isTv && animations;
}
