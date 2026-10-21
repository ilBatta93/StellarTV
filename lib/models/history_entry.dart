import 'content_type.dart';
import 'watch_completion_policy.dart';

class HistoryEntry {
  const HistoryEntry({
    required this.contentId,
    required this.type,
    required this.title,
    required this.posterUrl,
    required this.group,
    this.url = '',
    required this.position,
    required this.duration,
    required this.lastWatchedAt,
    this.seriesKey = '',
    this.seriesName = '',
    this.seriesPoster = '',
    this.watchedPercent = WatchCompletionPolicy.defaultPercent,
    this.manualWatched,
  });

  final String contentId;
  final ContentType type;
  final String title;
  final String posterUrl;
  final String group;
  final String url;
  final Duration position;
  final Duration duration;
  final DateTime lastWatchedAt;

  /// Series info for episodes, so Home can show the series poster and the
  /// player can find the next episode even after an app restart.
  final String seriesKey;
  final String seriesName;
  final String seriesPoster;
  final int watchedPercent;
  final bool? manualWatched;
  bool get isAutomaticallyWatched => !isLive && duration > Duration.zero &&
      position.inMilliseconds * 100 >= duration.inMilliseconds * WatchCompletionPolicy.normalize(watchedPercent);

  bool get isLive => type == ContentType.live;

  double? get progress {
    if (isLive || duration <= Duration.zero || position <= Duration.zero) {
      return null;
    }
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Completion is derived from real progress, never by changing the position.
  bool get isWatched {
    if (isLive) return false;
    return manualWatched ?? isAutomaticallyWatched;
  }

  /// Actual time left, rounded up so a partial minute never shows zero.
  int? get remainingMinutes {
    if (isLive || duration <= Duration.zero) return null;
    final remaining = duration.inMilliseconds - position.inMilliseconds;
    if (remaining <= 0) return 0;
    return (remaining / Duration.millisecondsPerMinute).ceil();
  }

  int? get remainingMovieMinutes =>
      type == ContentType.movie ? remainingMinutes : null;

  /// Detail actions show a countdown only after playback actually advances.
  int? get startedRemainingMinutes =>
      position > Duration.zero ? remainingMinutes : null;

  Duration? get resumePosition {
    if (isLive || duration <= Duration.zero || isAutomaticallyWatched) return null;
    if (position <= const Duration(seconds: 5)) {
      return null;
    }
    return position;
  }

  HistoryEntry copyWith({
    String? url,
    Duration? position,
    Duration? duration,
    DateTime? lastWatchedAt,
    int? watchedPercent,
    bool? manualWatched,
  }) {
    return HistoryEntry(
      contentId: contentId,
      type: type,
      title: title,
      posterUrl: posterUrl,
      group: group,
      url: url ?? this.url,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      lastWatchedAt: lastWatchedAt ?? this.lastWatchedAt,
      seriesKey: seriesKey,
      seriesName: seriesName,
      seriesPoster: seriesPoster,
      watchedPercent: watchedPercent ?? this.watchedPercent,
      manualWatched: manualWatched ?? this.manualWatched,
    );
  }

  static HistoryEntry? fromRow(Map<String, dynamic> row) {
    final id = row['content_id'];
    final watched = DateTime.tryParse(row['last_watched_at']?.toString() ?? '');
    if (id is! String || id.isEmpty || watched == null) return null;
    final typeName = row['content_type'];
    return HistoryEntry(
      contentId: id,
      type: ContentType.values.firstWhere(
        (t) => t.name == typeName,
        orElse: () => ContentType.live,
      ),
      title: row['title'] as String? ?? '',
      posterUrl: row['poster_url'] as String? ?? '',
      group: row['group_name'] as String? ?? '',
      url: row['url'] as String? ?? '',
      position: Duration(
        seconds: (row['position_seconds'] as num?)?.toInt() ?? 0,
      ),
      duration: Duration(
        seconds: (row['duration_seconds'] as num?)?.toInt() ?? 0,
      ),
      lastWatchedAt: watched.toLocal(),
    );
  }
}
