import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Network image kept in the disk cache and decoded straight from the file.
///
/// The cached_network_image provider reads every file into a Dart list
/// before decoding: on TV that was about 26 MB of short-lived buffers every
/// 25 s of grid scrolling, and the collections that followed paused the UI.
/// Here the engine reads the file itself, so the bytes never reach the
/// Dart heap.
@immutable
class DiskCachedImage extends ImageProvider<DiskCachedImage> {
  const DiskCachedImage(this.url, {required this.cacheManager});

  final String url;
  final BaseCacheManager cacheManager;

  @override
  Future<DiskCachedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<DiskCachedImage>(this);

  @override
  ImageStreamCompleter loadImage(
    DiskCachedImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(key, decode),
    scale: 1,
    debugLabel: key.url,
  );

  static Future<ui.Codec> _load(
    DiskCachedImage key,
    ImageDecoderCallback decode,
  ) async {
    final file = await key.cacheManager.getSingleFile(key.url);
    final buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
    try {
      return await decode(buffer);
    } catch (_) {
      // A truncated download would fail on every start: drop it so the
      // next request fetches it again.
      await key.cacheManager.removeFile(key.url).catchError((_) {});
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DiskCachedImage && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'DiskCachedImage("$url")';
}
