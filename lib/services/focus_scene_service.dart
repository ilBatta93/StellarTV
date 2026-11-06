import '../models/episode_metadata.dart';
import '../models/focus_scene_policy.dart';
import '../models/tmdb_item.dart';
import 'episode_metadata_service.dart';

/// Picture and episode shown by a selected cover that turned into a scene.
class FocusScene {
  const FocusScene({this.imageUrl, this.episode});

  /// Episode still or the title's scene still; null keeps the poster.
  final String? imageUrl;

  /// The episode the still belongs to (series only).
  final EpisodeMetadata? episode;
}

typedef EpisodeLoader = Future<EpisodeMetadata?> Function(
  TmdbItem item,
  int season,
  int episode,
);

/// Resolves the scene of the cover the remote rests on. One answer per
/// title and progress, kept in memory: never a request per card, and a
/// series asks TMDB for at most one season, stored on the device.
class FocusSceneService {
  FocusSceneService({EpisodeLoader? loadEpisode})
    : _loadEpisode = loadEpisode ?? EpisodeMetadataService.instance.episode;

  static final instance = FocusSceneService();

  final EpisodeLoader _loadEpisode;
  final _answers = <String, Future<FocusScene>>{};
  static const _limit = 80;

  Future<FocusScene> resolve(
    TmdbItem item, {
    SceneEpisode? last,
    bool lastWatched = false,
  }) {
    final key = '${item.key}|${last?.season}:${last?.episode}|$lastWatched';
    final known = _answers[key];
    if (known != null) return known;
    if (_answers.length >= _limit) _answers.remove(_answers.keys.first);
    final answer = _resolve(item, last, lastWatched);
    _answers[key] = answer;
    // A failure (offline) is retried on the next selection.
    answer.then<void>(
      (_) {},
      onError: (Object _) {
        _answers.remove(key);
      },
    );
    return answer;
  }

  Future<FocusScene> _resolve(
    TmdbItem item,
    SceneEpisode? last,
    bool lastWatched,
  ) async {
    final still = FocusScene(imageUrl: item.sceneUrl);
    final target = focusSceneEpisode(
      series: !item.isMovie,
      last: last,
      lastWatched: lastWatched,
    );
    if (target == null) return still;
    try {
      for (final candidate in [
        target,
        focusSceneFallback(last: last, lastWatched: lastWatched),
      ]) {
        if (candidate == null) continue;
        final episode = await _loadEpisode(
          item,
          candidate.season,
          candidate.episode,
        );
        if (episode == null) continue;
        return FocusScene(
          imageUrl: episode.stillUrl ?? item.sceneUrl,
          episode: episode,
        );
      }
    } catch (_) {
      // Offline: the series' own still is good enough.
    }
    return still;
  }
}
