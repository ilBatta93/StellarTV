import 'dart:ui' as ui;

import '../models/video_resolution_policy.dart';
import 'native_player_bridge.dart';

/// The screen's own resolution, read once. Engines use it for the "native"
/// cap; the settings screen shows it to the viewer.
class DisplayResolutionService {
  DisplayResolutionService._();

  static final instance = DisplayResolutionService._();

  DisplayResolution? _display;

  /// Null until [ensureLoaded] has run, or when no screen is reported.
  DisplayResolution? get display => _display;

  Future<DisplayResolution?> ensureLoaded() async {
    if (_display != null) return _display;
    _display =
        await NativePlayerBridge.instance.getDisplayResolution() ??
        _fromFlutter();
    return _display;
  }

  /// iOS and other platforms: the physical size Flutter draws into.
  static DisplayResolution? _fromFlutter() {
    final display = ui.PlatformDispatcher.instance.displays.firstOrNull;
    final size = display?.size;
    if (size == null || size.isEmpty) return null;
    return DisplayResolution(
      width: size.width.round(),
      height: size.height.round(),
    );
  }

  /// The cap the engines apply for [choice] on this screen.
  VideoSizeCap? capFor(MaxVideoResolution choice) =>
      videoSizeCap(choice, _display);
}
