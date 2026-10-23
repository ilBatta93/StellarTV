import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show ModalRoute;
import 'package:shared_preferences/shared_preferences.dart';

import 'image_cache_service.dart';
import 'device_type_service.dart';
import 'playback_work_policy.dart';

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

  /// True when no remote key arrived for at least [d] (startup heavy work).
  static bool stillFor(Duration d) =>
      DateTime.now().millisecondsSinceEpoch - _lastMs >= d.inMilliseconds;

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
  static const _maxPerRun = 12;

  static void warm(Iterable<String?> urls) {
    if (_running || PlaybackWorkPolicy.instance.blocksGuide) return;
    final pending = <String>[];
    for (final u in urls) {
      if (u == null || u.isEmpty || _seen.contains(u)) continue;
      pending.add(u);
      if (pending.length >= _maxPerRun) break;
    }
    if (pending.isEmpty) return;
    _running = true;
    unawaited(_drain(pending));
  }

  static Future<void> _drain(List<String> pending) async {
    try {
      for (var i = 0; i < pending.length; i++) {
        await RemoteNavigation.idle();
        if (RemoteNavigation.moving || PlaybackWorkPolicy.instance.blocksGuide)
          return;
        final u = pending[i];
        try {
          await AppImageCache.manager.getSingleFile(u);
          if (_seen.length >= 512) _seen.clear();
          _seen.add(u);
        } catch (_) {}
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
    // TV cards decode on demand, not all neighbouring rows at launch.
    if (DeviceTypeService.isTv ||
        w == null ||
        _running ||
        PlaybackWorkPolicy.instance.blocksGuide)
      return;
    final pending = <String>[];
    for (final u in urls) {
      if (u == null || u.isEmpty || !_seen.add('$w|$u')) continue;
      pending.add(u);
      if (pending.length >= 10) break;
    }
    if (pending.isEmpty) return;
    if (_seen.length > 512) _seen.clear();
    _running = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        for (var i = 0; i < pending.length; i += 3) {
          await RemoteNavigation.idle();
          if (!context.mounted ||
              RemoteNavigation.moving ||
              PlaybackWorkPolicy.instance.blocksGuide ||
              ModalRoute.of(context)?.isCurrent == false)
            return;
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

/// Memory pressure retires rebuildable decoded images, never disk/user data.
class TvImageMemoryGuard with WidgetsBindingObserver {
  TvImageMemoryGuard._();
  static final _instance = TvImageMemoryGuard._();
  static bool _installed = false;
  static final reducedRendering = ValueNotifier<bool>(false);
  static void install() {
    if (_installed) return;
    _installed = true;
    WidgetsBinding.instance.addObserver(_instance);
  }

  @override
  void didHaveMemoryPressure() {
    if (DeviceTypeService.isTv) reducedRendering.value = true;
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = 80;
    cache.maximumSizeBytes = 24 << 20;
    cache.clear();
    ImageWarmupService._seen.clear();
    PosterMemoryWarmup._seen.clear();
  }
}
