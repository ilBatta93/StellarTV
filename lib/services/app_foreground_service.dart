import 'dart:async';

import 'package:flutter/widgets.dart';

import 'foreground_policy.dart';
import 'native_player_bridge.dart';

/// Installed before providers so background progress writes stay local.
class AppForegroundService with WidgetsBindingObserver {
  AppForegroundService._();
  static final instance = AppForegroundService._();
  StreamSubscription<bool>? _display;
  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    ForegroundPolicy.instance.setResumed(
      state == null || state == AppLifecycleState.resumed,
    );
    var receivedEvent = false;
    _display ??= NativePlayerBridge.instance.displayChanges.listen((available) {
      receivedEvent = true;
      ForegroundPolicy.instance.setDisplayAvailable(available);
    });
    final available = await NativePlayerBridge.instance.isDisplayAvailable();
    if (!receivedEvent)
      ForegroundPolicy.instance.setDisplayAvailable(available);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ForegroundPolicy.instance.setResumed(state == AppLifecycleState.resumed);
  }
}
