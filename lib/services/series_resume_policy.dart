import '../models/history_entry.dart';
import '../models/series_details.dart';

/// Playback progress, not a manual badge, owns the current replay cursor.
bool replayEpisodeComplete(HistoryEntry entry) => entry.isAutomaticallyWatched;

/// An unresolved cursor is unknown, never evidence of a completed collection.
SeriesEpisode? nextEpisodeInSequence(
  List<SeriesEpisode> episodes,
  String contentId, {
  int? season,
  int? number,
}) {
  var index = episodes.indexWhere((e) => e.channel.id == contentId);
  if (index < 0 && season != null && number != null) {
    index = episodes.indexWhere(
      (e) => e.season == season && e.number == number,
    );
  }
  if (index < 0) throw StateError('episode not found in series details');
  return index + 1 < episodes.length ? episodes[index + 1] : null;
}

/// The most recent actual view wins over previously completed later episodes.
SeriesEpisode? latestSeriesReplay(
  List<SeriesEpisode> episodes,
  List<HistoryEntry> history,
) {
  HistoryEntry? latest;
  SeriesEpisode? current;
  final byId = {for (final episode in episodes) episode.channel.id: episode};
  for (final entry in history) {
    final episode = byId[entry.contentId];
    if (episode == null ||
        latest != null && !entry.lastWatchedAt.isAfter(latest.lastWatchedAt))
      continue;
    latest = entry;
    current = episode;
  }
  if (latest == null || current == null) return null;
  if (!replayEpisodeComplete(latest)) return current;
  return nextEpisodeInSequence(episodes, latest.contentId);
}

/// Cached end-of-sequence answers cannot hide a newer replay or another profile.
typedef SeriesReplayKey = (String?, String, DateTime, Duration, Duration, int);
SeriesReplayKey seriesReplayKey(String? profileId, HistoryEntry entry) => (
  profileId,
  entry.contentId,
  entry.lastWatchedAt,
  entry.position,
  entry.duration,
  entry.watchedPercent,
);
