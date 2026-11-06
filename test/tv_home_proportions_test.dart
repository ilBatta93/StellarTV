import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/home_layout_preferences.dart';
import 'package:stellar_tv/screens/catalog_page.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/services/image_warmup_service.dart';
import 'package:stellar_tv/widgets/tv_home_layout.dart';

/// TV Home proportions: banner sizes that really differ, a logo that stays
/// readable, and room for the focus zoom of covers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('banner sizes are clearly apart on TV, the phone keeps its own', () {
    final sizes = HomeBannerSize.values.map((s) => s.tvFraction).toList();
    for (var i = 1; i < sizes.length; i++) {
      expect(sizes[i] - sizes[i - 1], greaterThanOrEqualTo(0.07));
    }
    expect(HomeBannerSize.compact.fraction, 0.40);
    expect(HomeBannerSize.large.fraction, 0.48);
  });

  group('banner content', () {
    const line = 14 * 1.35;

    test('the plot gives way before the logo', () {
      final tight = tvHeroLayout(
        height: 153,
        fixed: 105,
        overviewLineHeight: line,
      );
      expect(tight.overviewLines, 0);
      expect(tight.logo, greaterThanOrEqualTo(40));
    });

    test('a taller banner keeps a comfortable logo and more plot', () {
      final roomy = tvHeroLayout(
        height: 230,
        fixed: 105,
        overviewLineHeight: line,
      );
      expect(roomy.overviewLines, 2);
      expect(roomy.logo, greaterThanOrEqualTo(56));
      final bigger = tvHeroLayout(
        height: 300,
        fixed: 105,
        overviewLineHeight: line,
      );
      expect(bigger.overviewLines, 3);
      expect(bigger.logo, 88);
    });

    test('plot off: all the room goes to the logo, capped', () {
      final r = tvHeroLayout(height: 120, fixed: 50);
      expect(r.overviewLines, 0);
      expect(r.logo, 64);
    });
  });

  group('room for the focus zoom', () {
    TvHomeLayout layout({double scale = 1.06, double ring = 2.5}) =>
        TvHomeLayout(
          rowHeight: 300,
          captionHeight: 18,
          focusScale: scale,
          ringWidth: ring,
          child: const SizedBox(),
        );

    test('a zoomed, ringed card fits its carousel', () {
      for (final scale in [1.0, 1.03, 1.06, 1.12]) {
        for (final ring in [0.0, 2.5, 4.0]) {
          final l = layout(scale: scale, ring: ring);
          expect(
            l.cardHeight * scale + 2 * ring,
            lessThanOrEqualTo(l.carouselHeight),
          );
          expect(
            l.rankedImageHeight * scale + 2 * ring,
            lessThanOrEqualTo(l.rankedHeight),
          );
        }
      }
    });

    test('a wider zoom makes covers smaller, not clipped', () {
      expect(
        layout(scale: 1.12).posterHeight,
        lessThan(layout(scale: 1.03).posterHeight),
      );
    });

    test('grid gaps leave room for both neighbours to grow', () {
      expect(tvFocusGap(16, 132, 1), 16);
      expect(tvFocusGap(16, 220, 1.12), closeTo(220 * 0.12 + 2, 1e-9));
      expect(tvFocusGap(10, 132, 1.03), 10);
    });
  });

  testWidgets('memory pressure pauses the banner trailer, then lets it back', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('stellartv/device'),
          (call) async => call.method == 'isTv' ? true : null,
        );
    await DeviceTypeService.initialize();
    debugDefaultTargetPlatformOverride = null;
    TvImageMemoryGuard.install();
    TvImageMemoryGuard.trailerPaused.value = false;
    tester.binding.handleMemoryPressure();
    expect(TvImageMemoryGuard.trailerPaused.value, isTrue);
    // A second warning restarts the wait.
    await tester.pump(const Duration(seconds: 40));
    tester.binding.handleMemoryPressure();
    await tester.pump(const Duration(seconds: 40));
    expect(TvImageMemoryGuard.trailerPaused.value, isTrue);
    await tester.pump(TvImageMemoryGuard.trailerCooldown);
    expect(TvImageMemoryGuard.trailerPaused.value, isFalse);
    // Images stay on the saving setting: only the trailer comes back.
    expect(TvImageMemoryGuard.reducedRendering.value, isTrue);
  });
}
