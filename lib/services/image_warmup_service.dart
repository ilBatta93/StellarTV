import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'image_cache_service.dart';

/// Downloads the posters of the first visible catalog titles in the
/// background, a few at a time, so opening a section does not wait on the
/// network. Files land in the shared disk cache (60 days), so they are
/// already there at the next app start; URLs already fetched in this run
/// are skipped.
/// Remote D-Pad activity. Background image work yields while the user is
/// moving, so the CPU and GPU of a TV box stay on the focus animation.
class RemoteNavigation {
  RemoteNavigation._();
  static int _lastMs = 0;
  static const quiet = Duration(milliseconds: 400);

  static void note() => _lastMs = DateTime.now().millisecondsSinceEpoch;

  static bool get moving =>
      DateTime.now().millisecondsSinceEpoch - _lastMs < quiet.inMilliseconds;

  /// Waits (bounded to ~3 s) until the remote has been still for [quiet].
  static Future<void> idle() async {
    for (var i = 0; i < 30 && moving; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

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
        await RemoteNavigation.idle();
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

/// Home posters are already on disk from earlier runs; what made them appear
/// late at start was reading and decoding them only once each card was
/// built. This remembers the decode width Home cards use on this device and,
/// right after the first frame, decodes the first visible posters into the
/// memory cache with exactly the same key the cards use, a few at a time.
/// Device-local only: nothing here touches the network beyond the existing
/// image cache, and it never runs while a video plays (Home is not shown).
class PosterMemoryWarmup {
  PosterMemoryWarmup._();

  static const _prefsKey = 'home_poster_decode_width_v1';
  static int? _width;
  static final _seen = <String>{};
  static bool _running = false;

  static int? get width => _width;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _width ??= prefs.getInt(_prefsKey);
    } catch (_) {}
  }

  static void noteWidth(int w) {
    if (_width == w) return;
    _width = w;
    unawaited(
      SharedPreferences.getInstance()
          .then((p) => p.setInt(_prefsKey, w))
          .then((_) {}, onError: (_) {}),
    );
  }

  static void warm(BuildContext context, Iterable<String?> urls) {
    final w = _width;
    if (w == null || _running) return;
    final pending = <String>[];
    for (final u in urls) {
      if (u == null || u.isEmpty || !_seen.add('$w|$u')) continue;
      pending.add(u);
      if (pending.length >= 10) break;
    }
    if (pending.isEmpty) return;
    _running = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        for (var i = 0; i < pending.length; i += 3) {
          await RemoteNavigation.idle();
          if (!context.mounted) return;
          await Future.wait([
            for (final u in pending.skip(i).take(3))
              precacheImage(
                ResizeImage(
                  CachedNetworkImageProvider(
                    tmdbSizedUrl(u, w),
                    cacheManager: AppImageCache.manager,
                  ),
                  width: w,
                ),
                context,
                onError: (_, _) {},
              ),
          ]);
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
      } finally {
        _running = false;
      }
    });
  }
}
