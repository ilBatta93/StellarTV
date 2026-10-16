import 'dart:async';

import 'image_cache_service.dart';

/// Downloads the posters of the first visible catalog titles in the
/// background, a few at a time, so opening a section does not wait on the
/// network. Files land in the shared disk cache (60 days), so they are
/// already there at the next app start; URLs already fetched in this run
/// are skipped.
class ImageWarmupService {
  ImageWarmupService._();

  static final _seen = <String>{};
  static bool _running = false;
  static const _maxPerRun = 120;

  static void warm(Iterable<String?> urls) {
    if (_running) return;
    final pending = <String>[];
    for (final u in urls) {
      if (u == null || u.isEmpty || !_seen.add(u)) continue;
      pending.add(u);
      if (pending.length >= _maxPerRun) break;
    }
    if (pending.isEmpty) return;
    _running = true;
    unawaited(_drain(pending));
  }

  static Future<void> _drain(List<String> pending) async {
    try {
      for (var i = 0; i < pending.length; i += 4) {
        await Future.wait([
          for (final u in pending.skip(i).take(4))
            AppImageCache.manager
                .downloadFile(u)
                .then((_) {})
                .catchError((_) {}),
        ]);
        // Yield between batches so scrolling stays fluid.
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } finally {
      _running = false;
    }
  }
}
