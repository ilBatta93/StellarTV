import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/frame_rate_policy.dart';
import 'device_type_service.dart';
import 'native_player_bridge.dart';

/// Auto frame rate on Android TV: one owner of the display mode, so two
/// players in a row (next episode, channel opened as a new page) never
/// switch the HDMI output back and forth.
class DisplayRefreshService {
  DisplayRefreshService._();

  static final instance = DisplayRefreshService._();

  /// The page that replaces the player asks for its rate within this time;
  /// only after it does the display go back to the system mode.
  static const releaseGrace = Duration(seconds: 3);

  final NativePlayerBridge _bridge = NativePlayerBridge.instance;

  /// Current display refresh in Hz, null until known or off Android TV.
  final ValueNotifier<double?> current = ValueNotifier(null);

  DisplayRefresh _display = DisplayRefresh.unknown;
  StreamSubscription<double>? _changes;
  Timer? _release;
  double? _requested;

  DisplayRefresh get display => _display;

  /// True when the system menu says "never": the TV may ignore the request.
  bool get systemMatchOff => _display.systemMatch == 'never';

  bool get _supported => DeviceTypeService.isTv;

  Future<void> ensureLoaded() async {
    if (!_supported) return;
    _changes ??= _bridge.refreshRateChanges.listen((hz) => current.value = hz);
    if (_display.rates.isNotEmpty) return;
    _display = await _bridge.getDisplayRefresh();
    current.value = _display.current ?? current.value;
  }

  /// Asks the display for the rate that suits [fps]. Returns the chosen rate,
  /// or null when the display keeps its mode.
  Future<double?> matchVideo(double? fps) async {
    if (!_supported) return null;
    _release?.cancel();
    await ensureLoaded();
    final rate = pickRefreshRate(fps, _display.rates);
    if (rate == null) return null;
    if (_requested != null && (_requested! - rate).abs() < 0.01) return rate;
    final now = current.value;
    if (_requested == null && now != null && (now - rate).abs() < 0.01) {
      return rate;
    }
    if (await _bridge.setPreferredRefreshRate(rate)) {
      _requested = rate;
      return rate;
    }
    return null;
  }

  /// The player is gone: give the display back after [releaseGrace].
  void release() {
    if (_requested == null) return;
    _release?.cancel();
    _release = Timer(releaseGrace, () {
      _requested = null;
      unawaited(_bridge.setPreferredRefreshRate(null));
    });
  }
}
