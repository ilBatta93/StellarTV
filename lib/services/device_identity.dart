import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'device_type_service.dart';

/// Builds the label the account website shows for this device's sessions.
/// Only type, platform and a sanitized model name: never identifiers.
class DeviceIdentity {
  DeviceIdentity._();

  static const cloudProtocol = 2;
  static String userAgent = 'StellarTV (cloud=$cloudProtocol)';

  static String sanitize(String value) => value
      .replaceAll(RegExp(r'[^A-Za-z0-9 ._+-]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  /// Format parsed by the website: StellarTV/<ver> (kind=..; platform=..; model=..)
  static String format({
    required String version,
    required String kind,
    required String platform,
    String? model,
  }) {
    final m = model == null ? '' : sanitize(model);
    final cut = m.length > 40 ? m.substring(0, 40) : m;
    return 'StellarTV/${sanitize(version)} (kind=$kind; platform=${sanitize(platform)}'
        '${cut.isEmpty ? '' : '; model=$cut'}; cloud=$cloudProtocol)';
  }

  static Future<void> initialize() async {
    try {
      final version = (await PackageInfo.fromPlatform()).version;
      final info = DeviceInfoPlugin();
      if (kIsWeb) return;
      if (defaultTargetPlatform == TargetPlatform.android) {
        final d = await info.androidInfo;
        final tv = DeviceTypeService.isTv;
        final phone = d.systemFeatures.contains('android.hardware.telephony');
        final brand = d.manufacturer.isEmpty ? '' : '${d.manufacturer} ';
        userAgent = format(
          version: version,
          kind: tv ? 'tv' : (phone ? 'phone' : 'tablet'),
          platform: DeviceTypeService.isFireTv
              ? 'Fire TV'
              : tv
              ? 'Android TV'
              : (phone ? 'Smartphone Android' : 'Tablet Android'),
          model: d.model.toLowerCase().startsWith(d.manufacturer.toLowerCase())
              ? d.model
              : '$brand${d.model}',
        );
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final d = await info.iosInfo;
        final ipad = d.model.toLowerCase().contains('ipad');
        userAgent = format(
          version: version,
          kind: ipad ? 'tablet' : 'phone',
          platform: ipad ? 'iPad' : 'iPhone',
          model: d.utsname.machine,
        );
      }
    } catch (_) {
      // Keeps the generic label: identification must never block startup.
    }
  }
}
