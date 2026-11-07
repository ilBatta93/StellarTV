import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// When the user last pressed a key or touched the screen, so background
/// work that must touch the UI thread (swapping in a refreshed catalog) can
/// wait for a quiet moment instead of stealing frames from navigation.
class UserActivity {
  UserActivity._();
  static final instance = UserActivity._();

  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  bool _attached = false;

  /// Starts listening to keys (remote, keyboard) and pointers. Idempotent.
  void attach() {
    if (_attached) return;
    _attached = true;
    HardwareKeyboard.instance.addHandler(_onKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  bool _onKey(KeyEvent _) {
    noteActivity();
    return false;
  }

  void _onPointer(PointerEvent _) => noteActivity();

  /// Records a key or touch now.
  void noteActivity() => _last = DateTime.now();

  /// Time since the last key or touch.
  Duration get idleFor => DateTime.now().difference(_last);

  /// Completes once nothing was pressed or touched for [quiet], or after
  /// [atMost] anyway, so continuous use cannot hold the work forever.
  Future<void> waitIdle({
    Duration quiet = const Duration(seconds: 3),
    Duration atMost = const Duration(minutes: 10),
  }) async {
    final deadline = DateTime.now().add(atMost);
    while (true) {
      final now = DateTime.now();
      final left = quiet - idleFor;
      final cap = deadline.difference(now);
      if (left <= Duration.zero || cap <= Duration.zero) return;
      var wait = left < cap ? left : cap;
      if (wait < const Duration(milliseconds: 250)) {
        wait = const Duration(milliseconds: 250);
      }
      await Future<void>.delayed(wait);
    }
  }
}
