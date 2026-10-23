import 'dart:async';

import '../models/streaming_platform.dart';
import '../models/tmdb_item.dart';
import 'playback_work_policy.dart';
import 'title_metadata_store.dart';
import 'tmdb_service.dart';

/// Official per-title streaming availability (TMDB watch providers, Italy,
/// subscription only), saved on the device for 30 days. This is the precise
/// answer for one title; platform catalogs only cover popular titles.
class TitleProvidersService {
  TitleProvidersService._();
  static final instance = TitleProvidersService._();

  final store = TitleMetadataStore<List<String>>(
    fileName: 'stellartv_title_providers_v1.json',
    encode: (v) => v,
    decode: (raw) => raw is List ? raw.whereType<String>().toList() : null,
  );
  final Set<String> _asked = {};
  final List<(String, TmdbItem)> _queue = [];
  bool _running = false;
  TmdbService? _tmdb;

  void attach(TmdbService tmdb) {
    _tmdb ??= tmdb;
    unawaited(store.load());
  }

  static String keyOf(TmdbItem item) =>
      '${item.isMovie ? 'movie' : 'tv'}:${item.id}';

  /// Platforms that verifiably offer [item], or null while not checked yet.
  List<StreamingPlatform>? platformsOf(TmdbItem item) {
    final key = keyOf(item);
    final names = store.valueOf(key);
    if (!TitleMetadataStore.disabled && !store.isFresh(key) && _asked.add(key)) {
      _queue.add((key, item));
      if (!_running) unawaited(_run());
    }
    if (names == null) return null;
    return [
      for (final p in StreamingPlatform.all)
        if (names.contains(p.name)) p,
    ];
  }

  Future<void> _run() async {
    final tmdb = _tmdb;
    if (tmdb == null) return;
    _running = true;
    try {
      await store.load();
      while (_queue.isNotEmpty) {
        if (PlaybackWorkPolicy.instance.blocksGuide) {
          await Future<void>.delayed(const Duration(seconds: 30));
          continue;
        }
        final (key, item) = _queue.removeAt(0);
        final ids = await tmdb.watchProviderIds(item);
        if (ids == null) continue;
        store.put(key, [
          for (final p in StreamingPlatform.all)
            if (p.providerIds.split('|').any(ids.contains)) p.name,
        ]);
      }
    } finally {
      _running = false;
    }
  }
}
