import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_type_service.dart';
import 'vod_diagnostics_log.dart';

/// Separate record from the live one: its own switch, its own file and its
/// own salt, so a film report never mixes with a channel report.
class VodDiagnosticsService extends ChangeNotifier {
  VodDiagnosticsService._();
  static final instance = VodDiagnosticsService._();
  VodDiagnosticsLog log = VodDiagnosticsLog();
  bool get enabled => log.enabled;
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  bool _writePending = false;
  File? _file;
  Map<String, Object?> _device = {};

  Future<void> initialize() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final salt = prefs.getString('vod_diagnostics_salt');
      log = VodDiagnosticsLog(salt: salt);
      await prefs.setString('vod_diagnostics_salt', log.salt);
      log.enabled = prefs.getBool('vod_diagnostics_enabled') ?? false;
      _file = File(
        '${(await getApplicationSupportDirectory()).path}/vod_diagnostics.json',
      );
      final file = _file;
      if (file != null &&
          await file.exists() &&
          await file.length() < 1024 * 1024) {
        final stored = jsonDecode(await file.readAsString());
        if (stored is List) {
          log.events.addAll(
            stored
                .whereType<Map>()
                .map((e) => Map<String, Object?>.from(e))
                .take(log.limit),
          );
        }
      }
    } catch (_) {
      /* diagnostics must never block playback */
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    await initialize();
    log.enabled = value;
    await (await SharedPreferences.getInstance()).setBool(
      'vod_diagnostics_enabled',
      value,
    );
    notifyListeners();
  }

  void record(
    String type, {
    String? session,
    Map<String, Object?> data = const {},
  }) {
    if (!enabled) return;
    log.add(type, session: session, data: data);
    _save();
    notifyListeners();
  }

  void _save() {
    if (_writePending) return;
    _writePending = true;
    // Snapshot only when the previous write runs: queue closures don't retain reports.
    _writes = _writes.then((_) async {
      _writePending = false;
      try {
        await _file?.writeAsString(jsonEncode(log.events), flush: true);
      } catch (_) {}
    });
  }

  Future<void> clear() async {
    log.events.clear();
    _save();
    await _writes;
    notifyListeners();
  }

  Future<String> report() async {
    await initialize();
    if (_device.isEmpty) {
      _device = {
        'platform': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'tv': DeviceTypeService.isTv,
        'fireTv': DeviceTypeService.isFireTv,
      };
      try {
        final info = await PackageInfo.fromPlatform();
        _device.addAll({'version': info.version, 'build': info.buildNumber});
        if (Platform.isAndroid) {
          final d = await DeviceInfoPlugin().androidInfo;
          _device.addAll({
            'manufacturer': d.manufacturer,
            'model': d.model,
            'sdk': d.version.sdkInt,
          });
        } else if (Platform.isIOS) {
          final d = await DeviceInfoPlugin().iosInfo;
          _device['model'] = d.utsname.machine;
        }
      } catch (_) {}
    }
    return log.report(_device);
  }

  Future<File> exportFile() async {
    final file = File(
      '${(await getTemporaryDirectory()).path}/StellarTV-diagnostica-film-serie.json',
    );
    return file.writeAsString(await report(), flush: true);
  }
}
