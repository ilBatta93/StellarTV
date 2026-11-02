/// Device-local deduplication; failures cool down without approving content.
class CatalogWorkQueue {
  final Map<String, String> pending = {};
  final Set<String> _active = {};
  final Map<String, DateTime> _retryAfter = {};
  final Map<String, int> _failures = {};

  /// Consecutive failures of one key cool down longer each time (2 min,
  /// 10 min, 1 h, then 6 h), so a title that keeps failing stops
  /// reaching the server every two minutes. Success resets the count.
  static Duration cooldown(int failures) => switch (failures) {
    <= 1 => const Duration(minutes: 2),
    2 => const Duration(minutes: 10),
    3 => const Duration(hours: 1),
    _ => const Duration(hours: 6),
  };

  void add(String key, String value, DateTime now) {
    if (_active.contains(key) || (_retryAfter[key]?.isAfter(now) ?? false)) {
      return;
    }
    pending.putIfAbsent(key, () => value);
  }

  Map<String, String> take(int limit) {
    final batch = Map<String, String>.fromEntries(pending.entries.take(limit));
    for (final key in batch.keys) {
      pending.remove(key);
      _active.add(key);
    }
    return batch;
  }

  void complete(String key) {
    pending.remove(key);
    _retryAfter.remove(key);
    _failures.remove(key);
  }

  void release(Iterable<String> keys, Set<String> resolved, DateTime now) {
    for (final key in keys) {
      _active.remove(key);
      if (resolved.contains(key)) {
        complete(key);
      } else {
        final failures = _failures[key] = (_failures[key] ?? 0) + 1;
        _retryAfter[key] = now.add(cooldown(failures));
      }
    }
    _retryAfter.removeWhere((_, deadline) => !deadline.isAfter(now));
  }
}
