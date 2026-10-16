import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// One disk cache for every poster, backdrop and photo. The library default
/// keeps only 200 files, so large catalogs kept re-downloading posters while
/// scrolling; this keeps a few thousand small resized images for 60 days.
class AppImageCache {
  AppImageCache._();
  static const _key = 'stellar_images_v1';
  static final manager = CacheManager(
    Config(
      _key,
      stalePeriod: const Duration(days: 60),
      maxNrOfCacheObjects: 8000,
    ),
  );
}
