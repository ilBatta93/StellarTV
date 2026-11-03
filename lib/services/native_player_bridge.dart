import 'dart:async';

import 'package:flutter/services.dart';

import '../models/video_resolution_policy.dart';

class DeviceMediaCapabilities {
  final List<String> hdrFormats;
  final Map<String, bool> decoders;

  const DeviceMediaCapabilities({
    required this.hdrFormats,
    required this.decoders,
  });

  static const unknown = DeviceMediaCapabilities(hdrFormats: [], decoders: {});
}

/// Refresh rates the display offers at its current resolution.
class DisplayRefresh {
  final double? current;
  final List<double> rates;

  /// Android 12+ system choice for content frame rate: 'never', 'seamless'
  /// or 'always'. Null when the system does not say.
  final String? systemMatch;

  const DisplayRefresh({this.current, this.rates = const [], this.systemMatch});

  static const unknown = DisplayRefresh();
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
      } else if (call.method == 'refreshRateChanged') {
        final rate = call.arguments;
        if (rate is num) _refreshController.add(rate.toDouble());
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

  final _refreshController = StreamController<double>.broadcast();

  /// Android: the display refresh rate after any mode change.
  Stream<double> get refreshRateChanges => _refreshController.stream;

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

  /// Android only: the panel's largest mode and the active one. Null
  /// elsewhere, where Flutter's own display size is used instead.
  Future<DisplayResolution?> getDisplayResolution() async {
    final raw = await _call<Map<Object?, Object?>>('getDisplayResolution');
    if (raw == null) return null;
    final w = raw['width'];
    final h = raw['height'];
    if (w is! int || h is! int || w <= 0 || h <= 0) return null;
    final cw = raw['currentWidth'];
    final ch = raw['currentHeight'];
    return DisplayResolution(
      width: w,
      height: h,
      currentWidth: cw is int ? cw : null,
      currentHeight: ch is int ? ch : null,
    );
  }

  Future<DisplayRefresh> getDisplayRefresh() async {
    final raw = await _call<Map<Object?, Object?>>('getDisplayRefresh');
    if (raw == null) return DisplayRefresh.unknown;
    final current = raw['current'];
    final rates = raw['rates'];
    final match = raw['systemMatch'];
    return DisplayRefresh(
      current: current is num ? current.toDouble() : null,
      rates: rates is List
          ? [
              for (final r in rates)
                if (r is num) r.toDouble(),
            ]
          : const [],
      systemMatch: match is String ? match : null,
    );
  }

  /// Asks the display for [rate] Hz at the current resolution; null gives
  /// the choice back to the system. False when no mode matches.
  Future<bool> setPreferredRefreshRate(double? rate) async =>
      await _call<bool>('setPreferredRefreshRate', {'rate': rate}) ?? false;

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
