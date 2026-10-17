/// Serializes resume saves so an explicit completion cannot be overwritten
/// by a timer, lifecycle event or disposal that was already in flight.
class PlaybackProgressWriter {
  Future<void> _tail = Future<void>.value();
  bool _completed = false;

  Future<void> save(Future<void> Function() write) {
    if (_completed) return Future<void>.value();
    final next = _tail.then((_) => write());
    _tail = next.catchError((Object _) {});
    return next;
  }

  Future<void> complete(Future<void> Function() write) {
    if (_completed) return _tail;
    _completed = true;
    final next = _tail.then((_) => write());
    _tail = next.catchError((Object _) {});
    return next;
  }
}
