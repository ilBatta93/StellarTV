import 'content_type.dart';

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

  bool get isLive => type == ContentType.live;

  double? get progress {
    if (isLive || duration <= Duration.zero || position <= Duration.zero) {
      return null;
    }
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Netflix-style "watched": 95% of the runtime reached (or less than two
  /// minutes left, which covers end credits on short episodes).
  bool get isWatched {
    if (isLive || duration <= Duration.zero) return false;
    final ratio = position.inMilliseconds / duration.inMilliseconds;
    return ratio >= 0.95 ||
        (position > Duration.zero &&
            duration - position <= const Duration(minutes: 2) &&
            duration >= const Duration(minutes: 10));
  }

  Duration? get resumePosition {
    if (isLive || duration <= Duration.zero || isWatched) return null;
    final remaining = duration - position;
    if (position <= const Duration(seconds: 5) ||
        remaining <= const Duration(minutes: 1)) {
      return null;
    }
    return position;
  }

  HistoryEntry copyWith({
    String? url,
    Duration? position,
    Duration? duration,
    DateTime? lastWatchedAt,
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
      position: Duration(seconds: (row['position_seconds'] as num?)?.toInt() ?? 0),
      duration: Duration(seconds: (row['duration_seconds'] as num?)?.toInt() ?? 0),
      lastWatchedAt: watched.toLocal(),
    );
  }
}
