/// Device-local visibility only; no account lease and no heartbeat.
class ForegroundPolicy {
  static final instance = ForegroundPolicy();
  bool _resumed = true;
  bool _displayAvailable = true;
  final Set<void Function()> _listeners = {};
  bool get active => _resumed && _displayAvailable;
  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);
  void setResumed(bool value) => _update(value, _displayAvailable);
  void setDisplayAvailable(bool value) => _update(_resumed, value);
  void _update(bool resumed, bool display) {
    final before = active;
    _resumed = resumed;
    _displayAvailable = display;
    if (before != active) {
      for (final listener in List<void Function()>.of(_listeners)) {
        listener();
      }
    }
  }
}
