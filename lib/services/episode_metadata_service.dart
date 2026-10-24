import 'dart:async';

import '../models/channel.dart';
import '../models/episode_metadata.dart';
import '../models/tmdb_item.dart';
import 'title_metadata_store.dart';
import 'tmdb_service.dart';
import 'imdb_rating_service.dart';
import 'playback_work_policy.dart';

/// Season-sized requests before playback; the player only reads device data.
class EpisodeMetadataService {
  EpisodeMetadataService._();
  static final instance = EpisodeMetadataService._();
  final store = TitleMetadataStore<EpisodeMetadata>(
    fileName: 'episode_metadata_v2.json',
    encode: (v) => v.toJson(),
    decode: EpisodeMetadata.parse,
  );
  final _channels = <String, String>{};
  final _pending = <String, Future<void>>{};
  void bind(Channel channel, int seriesId, int season, int episode) {
    _channels[channel.id] = 'tv:$seriesId:$season:$episode';
  }

  EpisodeMetadata? forChannel(Channel channel) =>
      store.valueOf(_channels[channel.id] ?? '');
  EpisodeMetadata? get(int id, int season, int episode) =>
      store.valueOf('tv:$id:$season:$episode');
  Future<void> prepare(
    TmdbItem item,
    int season,
    List<Channel> channels,
  ) async {
    for (final c in channels) {
      final number = c.episode;
      if (number != null) bind(c, item.id, season, number);
    }
    if (TitleMetadataStore.disabled) return;
    final key = '${item.id}:$season';
    return _pending.putIfAbsent(key, () async {
      try {
        await store.load();
        if (PlaybackWorkPolicy.instance.blocksGuide) return;
        final known = channels.where((c) => c.episode != null).toList();
        for (final c in known) {
          final number = c.episode;
          if (number != null)
            ImdbRatingService.instance.episodeRating(item.id, season, number);
        }
        if (known.isNotEmpty &&
            known.every(
              (c) => store.isFresh('tv:${item.id}:$season:${c.episode}'),
            ))
          return;
        final data = await TmdbService().seasonMetadata(item.id, season);
        for (final e in data) {
          if (PlaybackWorkPolicy.instance.blocksGuide) return;
          store.put(e.key, e);
          ImdbRatingService.instance.episodeRating(item.id, season, e.episode);
        }
      } catch (_) {
        /* Provider episode plots remain available offline. */
      } finally {
        _pending.remove(key);
      }
    });
  }
}
