import '../lib/services/tv_render_policy.dart';

void check(bool condition, String rule) {
  if (!condition) throw StateError(rule);
}

void main() {
  check(
    TvRenderPolicy.decodeLimit(isTv: true, memoryPressure: false) == 960,
    'TV normal decode',
  );
  check(
    TvRenderPolicy.decodeLimit(isTv: true, memoryPressure: true) == 640,
    'TV pressure decode',
  );
  check(
    TvRenderPolicy.decodeLimit(isTv: false, memoryPressure: true) == 1280,
    'Touch unchanged',
  );
  check(
    TvRenderPolicy.rowCacheFraction(memoryPressure: true) == 0,
    'Pressure neighbour dropped',
  );
  check(
    TvRenderPolicy.rowCacheFraction(memoryPressure: false) == 1.0,
    'Normal neighbour retained',
  );
  check(
    !TvRenderPolicy.backdropAllowed(isTv: true, memoryPressure: true),
    'Pressure decorative backdrop disabled',
  );
  check(
    TvRenderPolicy.backdropAllowed(isTv: false, memoryPressure: true),
    'Touch backdrop unchanged',
  );
  check(
    !TvRenderPolicy.startupFade(isTv: true, animations: true),
    'No TV splash fade',
  );
  check(
    TvRenderPolicy.startupFade(isTv: false, animations: true),
    'Touch animation preserved',
  );
  check(
    !TvRenderPolicy.startupFade(isTv: false, animations: false),
    'Reduced motion preserved',
  );
  check(
    TvRenderPolicy.homeBackdropDecodeLimit(memoryPressure: true) == 960,
    'Home retains only one bounded 960px backdrop under pressure',
  );
  check(
    TvRenderPolicy.homeBackdropDecodeLimit(memoryPressure: false) == 1280,
    'Normal Home backdrop remains bounded',
  );
  print('PASS: 12 rendering policy checks');
}
