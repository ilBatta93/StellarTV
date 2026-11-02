import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native device capabilities used to keep TV and touch presentation separate.
class DeviceTypeService {
  DeviceTypeService._();

  static const _channel = MethodChannel('stellartv/device');
  static bool _isTv = false;
  static bool _isFireTv = false;
  static bool get isFireTv => _isFireTv;

  static bool get isTv => _isTv;

  static int? _totalRamBytes;
  static bool _lowRam = false;

  /// Device RAM, null where the platform does not report it (iOS).
  static int? get totalRamBytes => _totalRamBytes;

  /// Android's own low-memory class (Go devices, 1 GB sticks).
  static bool get isLowRam => _lowRam;

  static Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      _isTv = await _channel.invokeMethod<bool>('isTv') ?? false;
      _isFireTv =
          _isTv && (await _channel.invokeMethod<bool>('isFireTv') ?? false);
    } on MissingPluginException {
      _isFireTv = false;
    } on PlatformException {
      _isFireTv = false;
    }
    // Optional: an older native side or an unexpected reply only means
    // the rewind buffer falls back to the per-device default.
    try {
      final memory = await _channel.invokeMethod<Object?>('memoryInfo');
      if (memory is Map) {
        final total = memory['totalBytes'];
        _totalRamBytes = total is num ? total.toInt() : null;
        _lowRam = memory['lowRam'] == true;
      }
    } catch (_) {
      _totalRamBytes = null;
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

  /// Closes the app completely (used by the explicit "close" choice on Home).
  static Future<void> closeApp() async {
    await SystemNavigator.pop();
  }
}
