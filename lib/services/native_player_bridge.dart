import 'dart:async';

import 'package:flutter/services.dart';

class DeviceMediaCapabilities {
  final List<String> hdrFormats;
  final Map<String, bool> decoders;

  const DeviceMediaCapabilities({
    required this.hdrFormats,
    required this.decoders,
  });

  static const unknown = DeviceMediaCapabilities(hdrFormats: [], decoders: {});
}

/// Android-only features (PiP, brightness, keep-awake). On other platforms
/// every call degrades to a no-op.
class NativePlayerBridge {
  NativePlayerBridge._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') {
        _pipController.add(call.arguments == true);
      } else if (call.method == 'displayChanged') {
        _displayController.add(call.arguments == true);
      } else if (call.method == 'screenOff') {
        _displayController.add(false);
        _screenOffController.add(null);
      }
    });
  }

  static final instance = NativePlayerBridge._();

  static const _channel = MethodChannel('stellartv/player');
  final _pipController = StreamController<bool>.broadcast();

  Stream<bool> get pipChanges => _pipController.stream;

  final _screenOffController = StreamController<void>.broadcast();
  final _displayController = StreamController<bool>.broadcast();
  Stream<bool> get displayChanges => _displayController.stream;

  /// Android: the display turned off, the device went to sleep or the HDMI
  /// output was unplugged/turned off (TV switched off with the remote).
  Stream<void> get screenOff => _screenOffController.stream;

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> isDisplayAvailable() async {
    try {
      return await _call<bool>('isDisplayAvailable')
              .timeout(const Duration(seconds: 2)) ??
          true;
    } on TimeoutException {
      return true;
    }
  }

  Future<bool> isPipSupported() async =>
      await _call<bool>('isPipSupported') ?? false;

  Future<bool> enterPip({int? width, int? height}) async =>
      await _call<bool>('enterPip', {'width': width, 'height': height}) ??
      false;

  Future<void> setAutoPip(bool enabled, {int? width, int? height}) =>
      _call<void>('setAutoPip', {
        'enabled': enabled,
        'width': width,
        'height': height,
      });

  /// Android: 'landscape' (sensor), 'portrait' or 'sensor'.
  Future<void> setOrientation(String mode) =>
      _call<void>('setOrientation', {'mode': mode});

  Future<void> setKeepScreenOn(bool enabled) =>
      _call<void>('setKeepScreenOn', {'enabled': enabled});

  Future<double?> getBrightness() => _call<double>('getBrightness');

  Future<void> setBrightness(double value) =>
      _call<void>('setBrightness', {'value': value});

  Future<void> resetBrightness() => setBrightness(-1);

  Future<DeviceMediaCapabilities> getCapabilities() async {
    final raw = await _call<Map<Object?, Object?>>('getCapabilities');
    if (raw == null) return DeviceMediaCapabilities.unknown;
    final hdr = raw['hdr'];
    final codecs = raw['codecs'];
    return DeviceMediaCapabilities(
      hdrFormats: hdr is List ? hdr.whereType<String>().toList() : const [],
      decoders: codecs is Map
          ? {
              for (final e in codecs.entries)
                if (e.key is String && e.value is bool)
                  e.key as String: e.value as bool,
            }
          : const {},
    );
  }
}
