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

/// TMDB serves every image in fixed widths. Grid cards decoded at ~300 px
/// were downloading and JPEG-decoding w500/w1280 originals, the main cause of
/// random hitches while scrolling Top rows. Picks the smallest published size
/// that still covers [decodeWidth] device pixels; never upscales the request.
String tmdbSizedUrl(String url, int? decodeWidth) {
  if (decodeWidth == null || decodeWidth <= 0) return url;
  final m = RegExp(r'^(https://image\.tmdb\.org/t/p/)w(\d+)(/.+)$').firstMatch(url);
  if (m == null) return url;
  final current = int.parse(m.group(2)!);
  const sizes = [185, 342, 500, 780, 1280];
  for (final w in sizes) {
    if (w >= current) break;
    if (w >= decodeWidth) return '${m.group(1)}w$w${m.group(3)}';
  }
  return url;
}
