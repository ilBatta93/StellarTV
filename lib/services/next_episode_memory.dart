import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_entry.dart';

/// The episode after a finished one, as Home last found it in the catalog.
class NextEpisodeHint {
  const NextEpisodeHint({required this.exists, this.season, this.number});

  final bool exists;
  final int? season;
  final int? number;
}

/// Device-only memory of Home's "is there a next episode?" checks. Without
/// it a series that has ended showed up in "Continua a guardare" for a few
/// seconds at every start, until the catalog check hid it again. Home still
/// re-checks in the background, so a newly released episode reappears.
class NextEpisodeMemory {
  NextEpisodeMemory._();
  static final instance = NextEpisodeMemory._();

  static const _prefsKey = 'home_next_episode_v1';
  static const _max = 300;

  final Map<String, NextEpisodeHint> _hints = {};
  bool _loaded = false;

  /// Same identity as `seriesReplayKey`: a newer view is a new question.
  static String keyOf(String? profileId, HistoryEntry e) =>
      '${profileId ?? ''}|${e.contentId}|'
      '${e.lastWatchedAt.millisecondsSinceEpoch}|'
      '${e.position.inSeconds}|${e.duration.inSeconds}|${e.watchedPercent}';

  /// Not memoised as a future: a read that never finished (an app or test
  /// torn down mid-start) must not leave every later caller waiting.
  Future<void> load() async {
    if (_loaded) return;
    await _read();
    _loaded = true;
  }

  Future<void> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return;
      map.forEach((key, value) {
        if (value is List && value.length == 3 && value[0] is bool) {
          _hints[key] = NextEpisodeHint(
            exists: value[0] as bool,
            season: value[1] is int ? value[1] as int : null,
            number: value[2] is int ? value[2] as int : null,
          );
        }
      });
    } catch (_) {
      // A damaged memory only means checking the catalog again.
    }
  }

  NextEpisodeHint? operator [](String key) => _hints[key];

  void put(String key, NextEpisodeHint hint) {
    final old = _hints[key];
    if (old != null &&
        old.exists == hint.exists &&
        old.season == hint.season &&
        old.number == hint.number) {
      return;
    }
    // Newest last, so trimming drops the oldest answers.
    _hints
      ..remove(key)
      ..[key] = hint;
    while (_hints.length > _max) {
      _hints.remove(_hints.keys.first);
    }
    _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          for (final e in _hints.entries)
            e.key: [e.value.exists, e.value.season, e.value.number],
        }),
      );
    } catch (_) {}
  }
}
