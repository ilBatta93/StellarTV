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

  bool get isLive => type == ContentType.live;

  double? get progress {
    if (isLive || duration <= Duration.zero || position <= Duration.zero) {
      return null;
    }
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  Duration? get resumePosition {
    if (isLive || duration <= Duration.zero) return null;
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
