import 'dart:math';

import 'foreground_policy.dart';

/// Shared by every session, including previews and MultiView. Opening and
/// buffering block cloud work; only an explicit pause/end releases that gate.
class PlaybackWorkPolicy {
  PlaybackWorkPolicy() {
    ForegroundPolicy.instance.addListener(_changed);
  }
  static final instance = PlaybackWorkPolicy();
  final Map<Object, bool> _sessions = {};
  final Set<void Function()> _listeners = {};
  bool get hasPlayback => _sessions.isNotEmpty;
  bool get blocksGuide =>
      !ForegroundPolicy.instance.active || _sessions.isNotEmpty;

  /// Catalog files wait until every session is gone and the app is visible.
  /// A paused preview still counts as open: the copy stays in memory.
  bool get blocksCatalogWrite =>
      !ForegroundPolicy.instance.active || _sessions.isNotEmpty;
  bool get blocksCloud =>
      !ForegroundPolicy.instance.active ||
      _sessions.values.any((blocked) => blocked);
  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);
  void update(Object owner, {required bool cloudBlocked}) {
    if (_sessions[owner] == cloudBlocked && _sessions.containsKey(owner))
      return;
    _sessions[owner] = cloudBlocked;
    _changed();
  }

  void remove(Object owner) {
    if (_sessions.remove(owner) != null) _changed();
  }

  void _changed() {
    for (final listener in List<void Function()>.of(_listeners)) listener();
  }

  static Duration conflictDelay(Random random) =>
      Duration(milliseconds: 250 + random.nextInt(151));
}
