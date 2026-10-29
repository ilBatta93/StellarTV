import 'package:shared_preferences/shared_preferences.dart';

/// How many simultaneous playback sockets the source allows.
///
/// One slot keeps the next stream behind a finished release. More than one
/// lets the next stream start while the previous player is still closing.
class StreamSlotPolicy {
  StreamSlotPolicy._();
  static final instance = StreamSlotPolicy._();
  static const storageKey = 'source_max_connections';
  static const releaseTimeoutKey = 'source_release_timeout_seconds';

  static const defaultReleaseTimeout = 8; // Raised from 5s for live streams.

  int _max = 1;
  int _releaseTimeout = defaultReleaseTimeout;

  int get maxConnections => _max;
  int get releaseTimeout => _releaseTimeout;

  bool get allowsOverlap => _max > 1;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(storageKey);
    if (stored != null && stored > 0) _max = stored;
    await loadReleaseTimeout();
  }

  Future<void> loadReleaseTimeout() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(releaseTimeoutKey);
    if (stored != null && stored > 0) _releaseTimeout = stored;
  }

  Future<void> remember(Object? raw) async {
    final parsed = parseMaxConnections(raw);
    if (parsed == null || parsed <= 0 || parsed == _max) return;
    _max = parsed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(storageKey, parsed);
  }

  Future<void> setReleaseTimeout(int seconds) async {
    if (seconds <= 0 || seconds == _releaseTimeout) return;
    _releaseTimeout = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(releaseTimeoutKey, seconds);
  }
}

int? parseMaxConnections(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString());
}