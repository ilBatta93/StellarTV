/// Device-local deduplication; failures cool down without approving content.
class CatalogWorkQueue {
  final Map<String, String> pending = {};
  final Set<String> _active = {};
  final Map<String, DateTime> _retryAfter = {};

  void add(String key, String value, DateTime now) {
    if (_active.contains(key) || (_retryAfter[key]?.isAfter(now) ?? false))
      return;
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
  }

  void release(Iterable<String> keys, Set<String> resolved, DateTime now) {
    for (final key in keys) {
      _active.remove(key);
      if (resolved.contains(key)) {
        complete(key);
      } else {
        _retryAfter[key] = now.add(const Duration(minutes: 2));
      }
    }
    _retryAfter.removeWhere((_, deadline) => !deadline.isAfter(now));
  }
}
