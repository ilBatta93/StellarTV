import 'dart:async';

import 'foreground_policy.dart';

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

/// Reloads the playlist only when the user-chosen interval has elapsed
/// since the last *successful* complete download (persisted on the device).
///
/// The playlist saved on the device is used at every start: opening the app
/// never re-downloads it. When an update is due at start-up it is delayed a
/// little, so the first navigation stays smooth.
class PlaylistRefreshService {
  PlaylistRefreshService(this._reload) {
    ForegroundPolicy.instance.addListener(_visibilityChanged);
  }
  bool _enabled = true;
  int _epoch = 0;
  void _visibilityChanged() {
    _epoch++;
    _timer?.cancel();
    if (_enabled && ForegroundPolicy.instance.active) unawaited(schedule());
  }

  final Future<void> Function() _reload;
  Timer? _timer;
  bool _running = false;

  static const _intervalKey = 'playlist_refresh_minutes';
  static const _lastRunKey = 'playlist_refresh_last_run';

  /// Delay before an overdue update starts after the app opens.
  static const startupDelay = Duration(seconds: 45);

  Future<int> loadIntervalMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    // Default: refresh once a day until the user picks another value.
    return prefs.getInt(_intervalKey) ?? PlaylistRefreshInterval.daily.minutes;
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

  /// Records a complete, successful download of every section.
  Future<void> markRun([DateTime? at]) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lastRunKey,
      (at ?? DateTime.now()).toIso8601String(),
    );
  }

  Future<void> clearLastRun() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastRunKey);
  }

  /// Time left before the next automatic update (null = never).
  Future<Duration?> timeUntilDue() async {
    final minutes = await loadIntervalMinutes();
    if (minutes <= 0) return null;
    final last = await lastRun();
    if (last == null) return Duration.zero;
    final remaining =
        Duration(minutes: minutes) - DateTime.now().difference(last);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Arms a single timer for the next update; it never runs immediately.
  Future<void> schedule() async {
    _enabled = true;
    _timer?.cancel();
    final epoch = ++_epoch;
    final remaining = await timeUntilDue();
    if (epoch != _epoch || !ForegroundPolicy.instance.active || !_enabled)
      return;
    if (remaining == null) return;
    final wait = remaining < startupDelay ? startupDelay : remaining;
    _timer = Timer(wait, _run);
  }

  Future<void> _run() async {
    if (_running || !_enabled || !ForegroundPolicy.instance.active) return;
    _running = true;
    try {
      // The reload records the timestamp itself, only when every section
      // downloaded fine: a failed attempt is retried at the next check.
      await _reload();
    } catch (_) {
    } finally {
      _running = false;
    }
    final remaining = await timeUntilDue();
    if (remaining == null || !_enabled || !ForegroundPolicy.instance.active)
      return;
    _timer?.cancel();
    // Failed attempt: try again in 30 minutes instead of a full interval.
    _timer = Timer(
      remaining == Duration.zero ? const Duration(minutes: 30) : remaining,
      _run,
    );
  }

  void stop() {
    _enabled = false;
    _epoch++;
    _timer?.cancel();
  }

  void dispose() {
    stop();
    ForegroundPolicy.instance.removeListener(_visibilityChanged);
  }
}
