/// Serial mute-before-unmute: fast focus changes never create two audio owners.
class MultiViewAudio<T> {
  MultiViewAudio(this.setVolume);
  final Future<void> Function(T, double) setVolume;
  final List<T> _items = [];
  final Set<T> _known = {};
  T? _selected;
  bool _suspended = false;
  bool _disposed = false;
  Future<void> _pending = Future.value();

  Future<void> update(
    Iterable<T> items,
    T? selected, {
    bool suspended = false,
  }) {
    _known.addAll(_items);
    _items
      ..clear()
      ..addAll(items);
    _known.addAll(_items);
    _selected = selected;
    _suspended = suspended;
    _pending = _pending.catchError((Object _) {}).then((_) async {
      if (_disposed) return;
      final current = List<T>.of(_known);
      for (final item in current) {
        try {
          await setVolume(item, 0);
        } catch (_) {}
      }
      _known.removeWhere((item) => !_items.contains(item));
      final owner = _selected;
      if (_disposed || _suspended || owner == null || !_items.contains(owner))
        return;
      try {
        await setVolume(owner, 1);
      } catch (_) {}
    });
    return _pending;
  }

  void dispose() {
    _disposed = true;
    _items.clear();
    _known.clear();
    _selected = null;
  }
}
