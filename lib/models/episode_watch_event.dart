import 'dart:convert';

/// Control records are independent from playback positions and timestamps.
class EpisodeWatchEvent {
  static const kind = '__stellar_seen_v1';
  static const prefix = '__stellar_seen_v1:';
  final String target;
  final int value;
  final DateTime at;
  final bool suggestion;
  final String? seriesId;
  const EpisodeWatchEvent(
    this.target,
    this.value,
    this.at, {
    this.suggestion = false,
    this.seriesId,
  });
  String get key =>
      '$prefix${suggestion ? 's' : 'e'}:${base64Url.encode(utf8.encode(target))}';
  bool? get watched => value == 1
      ? true
      : value == 0
      ? false
      : null;
  Map<String, dynamic> toJson() => {
    'id': key,
    'type': kind,
    'name': base64Url.encode(utf8.encode(target)),
    'pos': value,
    'group': suggestion ? 'suggestion' : 'episode',
    'watched': at.toUtc().toIso8601String(),
    if (seriesId != null) 'skey': seriesId,
  };
  static EpisodeWatchEvent? parse(Map<String, dynamic> row) {
    if (row['type'] != kind) return null;
    final at = DateTime.tryParse(row['watched']?.toString() ?? '');
    final value = row['pos'];
    if (at == null || value is! int || value < 0 || value > 3) return null;
    try {
      final target = utf8.decode(base64Url.decode(row['name'] as String));
      if (target.isEmpty) return null;
      final suggestion = row['group'] == 'suggestion';
      if (suggestion && value != 2 && value != 3 ||
          !suggestion && value != 0 && value != 1 && value != 3) {
        return null;
      }
      final event = EpisodeWatchEvent(
        target,
        value,
        at,
        suggestion: suggestion,
        seriesId: row['skey'] is String ? row['skey'] as String : null,
      );
      return event.key == row['id'] ? event : null;
    } catch (_) {
      return null;
    }
  }

  bool newerThan(EpisodeWatchEvent other) =>
      at.isAfter(other.at) ||
      at.isAtSameMomentAs(other.at) && value < other.value;
}
