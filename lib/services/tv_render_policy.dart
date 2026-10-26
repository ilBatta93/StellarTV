/// Device-local rendering limits. Pressure mode lasts until process restart,
/// avoiding a timer that reintroduces images while the user is navigating.
class TvRenderPolicy {
  static int decodeLimit({required bool isTv, required bool memoryPressure}) =>
      isTv ? (memoryPressure ? 640 : 960) : 1280;
  static int homeBackdropDecodeLimit({required bool memoryPressure}) =>
      memoryPressure ? 960 : 1280;
  static double rowCacheFraction({required bool memoryPressure}) =>
      memoryPressure ? 0 : 1;
  static bool backdropAllowed({
    required bool isTv,
    required bool memoryPressure,
  }) => !isTv || !memoryPressure;
  static bool startupFade({required bool isTv, required bool animations}) =>
      !isTv && animations;
}
