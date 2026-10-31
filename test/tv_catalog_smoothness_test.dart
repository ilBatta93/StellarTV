import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/player/mediakit_engine.dart';
import 'package:stellar_tv/services/catalog_rating_service.dart';
import 'package:stellar_tv/services/work_slicer.dart';

void main() {
  test('year-tagged titles take the direct TMDB lane', () {
    expect(CatalogRatingService.needsDirectLookup('Dune (2021)'), isTrue);
    expect(CatalogRatingService.needsDirectLookup('Dune'), isFalse);
    expect(CatalogRatingService.needsDirectLookup('2001 Odissea'), isTrue);
  });

  test('live catch-up only on full-screen TV live', () {
    expect(
      MediaKitEngine.liveCatchUp(tv: true, live: true, preview: false),
      isTrue,
    );
    expect(
      MediaKitEngine.liveCatchUp(tv: true, live: true, preview: true),
      isFalse,
    );
    expect(
      MediaKitEngine.liveCatchUp(tv: true, live: false, preview: false),
      isFalse,
    );
    expect(
      MediaKitEngine.liveCatchUp(tv: false, live: true, preview: false),
      isFalse,
    );
  });

  test('slicer yields only after its budget is spent', () async {
    final slicer = WorkSlicer(budget: Duration.zero);
    var yields = 0;
    for (var i = 0; i < 256; i++) {
      final pause = slicer.pause();
      if (pause is Future) {
        yields++;
        await pause;
      }
    }
    expect(yields, 4);
    final lazy = WorkSlicer(budget: const Duration(hours: 1));
    for (var i = 0; i < 256; i++) {
      expect(lazy.pause(), isNull);
    }
  });
}
