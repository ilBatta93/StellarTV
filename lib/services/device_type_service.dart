import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native device capabilities used to keep TV and touch presentation separate.
class DeviceTypeService {
  DeviceTypeService._();

  static const _channel = MethodChannel('stellartv/device');
  static bool _isTv = false;

  static bool get isTv => _isTv;

  static Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      _isTv = await _channel.invokeMethod<bool>('isTv') ?? false;
    } on PlatformException {
      _isTv = false;
    }
  }

  /// Sends the app to the background (keeps it running) instead of closing.
  static Future<void> moveToBackground() async {
    try {
      await _channel.invokeMethod('moveToBack');
    } on PlatformException {
      await SystemNavigator.pop();
    }
  }
}
