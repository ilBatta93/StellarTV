import 'dart:io';
import 'dart:isolate';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

import 'playback_work_policy.dart';
import 'title_metadata_store.dart';

/// One disk cache for every poster, backdrop and photo.
///
/// The library counts files, not bytes, and only trims after a later read.
/// A long scroll of a large catalog therefore kept every original image.
/// This store keeps a few thousand files and a hard byte budget: the oldest
/// images are removed until the folder is back under the limit.
class AppImageCache {
  AppImageCache._();
  static const _key = 'stellar_images_v1';

  /// About 350 MB. A full-size poster is tens of kilobytes; the previous
  /// unbounded hour of scrolling reached about 1.5 GB.
  static const budgetBytes = 350 << 20;

  static final manager = CacheManager(
    Config(
      _key,
      stalePeriod: const Duration(days: 60),
      maxNrOfCacheObjects: 2000,
    ),
  );

  static Future<void>? _trim;
  static DateTime _nextCheck = DateTime.fromMillisecondsSinceEpoch(0);

  /// Coalesces checks while the grid is scrolling. No work in tests.
  static void noteActivity() {
    if (TitleMetadataStore.disabled) return;
    final now = DateTime.now();
    if (now.isBefore(_nextCheck)) return;
    _nextCheck = now.add(const Duration(seconds: 25));
    enforceBudget();
  }

  static void enforceBudget() {
    if (TitleMetadataStore.disabled) return;
    _trim ??= () async {
      try {
        if (PlaybackWorkPolicy.instance.blocksGuide) return;
        final root = (await getTemporaryDirectory()).path;
        await Isolate.run(() => trimCacheDirectory('$root/$_key', budgetBytes));
        try {
          // A cache read schedules the library's own file-count cleanup.
          await manager.getFileFromCache('__budget__');
        } catch (_) {}
      } catch (_) {
      } finally {
        _trim = null;
      }
    }();
  }
}

/// Removes the oldest files until the directory is under 85% of [budgetBytes].
/// Database files that index the cache are left in place.
int trimCacheDirectory(String path, int budgetBytes) {
  final dir = Directory(path);
  if (!dir.existsSync()) return 0;
  final files = <File>[];
  var total = 0;
  for (final entity in dir.listSync(followLinks: false)) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last.toLowerCase();
    if (name.endsWith('.db') ||
        name.endsWith('.db-wal') ||
        name.endsWith('.db-shm') ||
        name.endsWith('.json')) {
      continue;
    }
    final length = entity.lengthSync();
    total += length;
    files.add(entity);
  }
  if (total <= budgetBytes) return 0;
  files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
  final target = (budgetBytes * 0.85).round();
  var removed = 0;
  for (final file in files) {
    if (total <= target) break;
    final length = file.lengthSync();
    try {
      file.deleteSync();
      total -= length;
      removed += length;
    } catch (_) {}
  }
  return removed;
}

/// TMDB serves every image in fixed widths. Grid cards decoded at ~300 px
/// were downloading and JPEG-decoding w500/w1280 originals, the main cause of
/// random hitches while scrolling Top rows. Picks the smallest published size
/// that still covers [decodeWidth] device pixels; never upscales the request.
String tmdbSizedUrl(String url, int? decodeWidth) {
  if (decodeWidth == null || decodeWidth <= 0) return url;
  final m = RegExp(r'^(https://image\.tmdb\.org/t/p/)w(\d+)(/.+)$')
      .firstMatch(url);
  if (m == null) return url;
  final current = int.parse(m.group(2)!);
  const sizes = [185, 342, 500, 780, 1280];
  for (final w in sizes) {
    if (w >= current) break;
    if (w >= decodeWidth) return '${m.group(1)}w$w${m.group(3)}';
  }
  return url;
}
