import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

enum PlaylistRefreshInterval {
  off('Mai (manuale)', 0),
  h1('Ogni ora', 60),
  h6('Ogni 6 ore', 360),
  h12('Ogni 12 ore', 720),
  daily('Una volta al giorno', 1440),
  weekly('Una volta a settimana', 10080);

  final String label;
  final int minutes;
  const PlaylistRefreshInterval(this.label, this.minutes);

  static PlaylistRefreshInterval fromMinutes(int? minutes) =>
      values.where((v) => v.minutes == (minutes ?? 0)).firstOrNull ?? off;
}

/// Reloads the Xtream playlist at a user-chosen interval while the app
/// is running. The last refresh time is persisted so the check also fires
/// shortly after each app start when the interval has already elapsed.
class PlaylistRefreshService {
  PlaylistRefreshService(this._reload);

  final Future<void> Function() _reload;
  Timer? _timer;

  static const _intervalKey = 'playlist_refresh_minutes';
  static const _lastRunKey = 'playlist_refresh_last_run';

  Future<int> loadIntervalMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_intervalKey) ?? 0;
  }

  Future<void> saveIntervalMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_intervalKey, minutes);
    await schedule();
  }

  Future<DateTime?> lastRun() async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(prefs.getString(_lastRunKey) ?? '');
  }

  Future<void> schedule() async {
    _timer?.cancel();
    final minutes = await loadIntervalMinutes();
    if (minutes <= 0) return;

    final prefs = await SharedPreferences.getInstance();
    final last = DateTime.tryParse(prefs.getString(_lastRunKey) ?? '');
    final due = last == null ||
        DateTime.now().difference(last) >= Duration(minutes: minutes);

    if (due) {
      await _runAndMark();
      _timer = Timer.periodic(Duration(minutes: minutes), (_) => _runAndMark());
    } else {
      final remaining = Duration(minutes: minutes) - DateTime.now().difference(last);
      _timer = Timer(remaining, () async {
        await _runAndMark();
        _timer = Timer.periodic(
            Duration(minutes: minutes), (_) => _runAndMark());
      });
    }
  }

  Future<void> _runAndMark() async {
    try {
      await _reload();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _lastRunKey, DateTime.now().toIso8601String());
    } catch (_) {
      // Keep the previous timestamp: retry on the next tick.
    }
  }

  void stop() => _timer?.cancel();
}
