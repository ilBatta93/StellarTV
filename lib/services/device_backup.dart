import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device_backup_policy.dart';
import 'device_type_service.dart';

/// Full device backup: every preference, every secure-storage entry and the
/// files of the support folder, as one gzip-compressed JSON manifest. The
/// bytes never leave the device in clear: [BackupTransfer] seals them for
/// the phone, which stores them under a password.
class DeviceBackup {
  const DeviceBackup._();

  /// Same options as the services that own each store: the backup must read
  /// and write exactly where they do.
  static const Map<String, FlutterSecureStorage> stores = {
    // settings_service.dart
    'settings': FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    ),
    // personal_vault.dart
    'vault': FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    ),
    // vpn_service.dart
    'vpn': FlutterSecureStorage(),
  };

  /// Builds the backup of this device. [account] is the signed-in account,
  /// only used to warn when restoring on another one.
  static Future<Uint8List> create({String? account}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final prefMap = <String, Object>{};
    for (final key in prefs.getKeys()) {
      if (!DeviceBackupPolicy.keepsPref(key)) continue;
      final value = DeviceBackupPolicy.encodePref(prefs.get(key));
      if (value != null) prefMap[key] = value;
    }
    final secure = <String, Map<String, String>>{};
    for (final e in stores.entries) {
      try {
        secure[e.key] = {
          for (final s in (await e.value.readAll()).entries)
            if (DeviceBackupPolicy.keepsSecret(s.key)) s.key: s.value,
        };
      } catch (_) {
        // An unreadable store (keystore reset) is skipped, not fatal.
        secure[e.key] = const {};
      }
    }
    var version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {}
    final dir = (await getApplicationSupportDirectory()).path;
    final header = {
      'created': DateTime.now().toUtc().toIso8601String(),
      'app': version,
      'platform': Platform.operatingSystem,
      'tv': DeviceTypeService.isTv,
      'account': account,
    };
    return Isolate.run(() => buildBackup(dir, header, prefMap, secure));
  }

  /// Summary of [payload], or null when it is not a readable backup.
  static Future<DeviceBackupSummary?> inspect(List<int> payload) {
    final bytes = Uint8List.fromList(payload);
    return Isolate.run(() {
      try {
        return DeviceBackupSummary.fromManifest(decodeManifest(bytes));
      } catch (_) {
        return null;
      }
    });
  }

  /// Replaces this device's data with [payload] and returns how many
  /// protected entries could not be written. The account session and the
  /// sync markers of this device stay as they are. The app must close right
  /// after: services still hold the old state in memory.
  static Future<int> restore(List<int> payload) async {
    final dir = (await getApplicationSupportDirectory()).path;
    final bytes = Uint8List.fromList(payload);
    // Files first: every file is decoded before anything is replaced, so a
    // damaged backup leaves the device untouched.
    final data = await Isolate.run(() => restoreFiles(dir, bytes));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final restored = <String>{};
    final prefMap = data['prefs'];
    if (prefMap is Map) {
      for (final e in prefMap.entries) {
        final key = e.key;
        if (key is! String || !DeviceBackupPolicy.keepsPref(key)) continue;
        final ok = switch (DeviceBackupPolicy.decodePref(e.value)) {
          final String v => await prefs.setString(key, v),
          final bool v => await prefs.setBool(key, v),
          final int v => await prefs.setInt(key, v),
          final double v => await prefs.setDouble(key, v),
          final List<String> v => await prefs.setStringList(key, v),
          _ => false,
        };
        if (ok) restored.add(key);
      }
    }
    // Then the settings this device had and the backup has not.
    for (final key in prefs.getKeys().toList()) {
      if (DeviceBackupPolicy.keepsPref(key) && !restored.contains(key)) {
        await prefs.remove(key);
      }
    }
    var failed = 0;
    final secure = data['secure'];
    if (secure is Map) {
      for (final e in stores.entries) {
        final entries = secure[e.key];
        if (entries is! Map) continue;
        for (final s in entries.entries) {
          if (s.key is! String || s.value is! String) continue;
          if (!DeviceBackupPolicy.keepsSecret(s.key as String)) continue;
          try {
            await e.value.write(key: s.key as String, value: s.value as String);
          } catch (_) {
            failed++;
          }
        }
      }
    }
    return failed;
  }
}

/// Manifest from backup bytes (gzip JSON).
Object? decodeManifest(Uint8List bytes) =>
    jsonDecode(utf8.decode(gzip.decode(bytes)));

/// Reads the support folder at [dir] and writes the whole backup. Runs in an
/// isolate: it reads and compresses every file.
Uint8List buildBackup(
  String dir,
  Map<String, Object?> header,
  Map<String, Object> prefs,
  Map<String, Map<String, String>> secure,
) {
  final files = <String, String>{};
  final skipped = <String>[];
  var total = 0;
  final root = Directory(dir);
  // Smallest first: the size limits then leave out only the largest files.
  final paths = <(File, int)>[];
  if (root.existsSync()) {
    for (final e in root.listSync(recursive: true, followLinks: false)) {
      if (e is! File || !DeviceBackupPolicy.keepsFile(_relative(dir, e.path))) {
        continue;
      }
      try {
        paths.add((e, e.lengthSync()));
      } catch (_) {}
    }
  }
  paths.sort((a, b) => a.$2.compareTo(b.$2));
  for (final (f, size) in paths) {
    final rel = _relative(dir, f.path);
    if (size > DeviceBackupPolicy.maxFileBytes ||
        total + size > DeviceBackupPolicy.maxTotalBytes) {
      skipped.add(rel);
      continue;
    }
    try {
      files[rel] = base64.encode(gzip.encode(f.readAsBytesSync()));
      total += size;
    } catch (_) {
      skipped.add(rel);
    }
  }
  final manifest = {
    'format': DeviceBackupPolicy.format,
    'version': DeviceBackupPolicy.version,
    'summary': {
      ...header,
      'prefs': prefs.length,
      'secrets': secure.values.fold<int>(0, (n, m) => n + m.length),
      'files': files.length,
      'bytes': total,
      'skipped': skipped,
    },
    'prefs': prefs,
    'secure': secure,
    'files': files,
  };
  return Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(manifest))));
}

const _staging = '.restore_staging';

/// Replaces the support-folder files at [dir] with those of the backup and
/// returns its preferences and secure entries. Every file is decoded into a
/// staging folder first: a damaged backup throws before anything changes.
/// Files the backup had to skip, and downloads, stay as they are on this
/// device. Runs in an isolate.
Map<String, Object?> restoreFiles(String dir, Uint8List bytes) {
  final manifest = decodeManifest(bytes);
  if (DeviceBackupSummary.fromManifest(manifest) == null ||
      manifest is! Map ||
      manifest['prefs'] is! Map ||
      manifest['secure'] is! Map ||
      manifest['files'] is! Map) {
    throw const FormatException('Backup non valido');
  }
  final summary = manifest['summary'] as Map;
  final skipped = {
    if (summary['skipped'] is List)
      for (final e in summary['skipped'] as List)
        if (e is String) e,
  };
  final files = manifest['files'] as Map;
  final staging = Directory('$dir/$_staging');
  if (staging.existsSync()) staging.deleteSync(recursive: true);
  final staged = <String>[];
  try {
    for (final e in files.entries) {
      final rel = e.key;
      if (rel is! String ||
          e.value is! String ||
          !DeviceBackupPolicy.keepsFile(rel)) {
        continue;
      }
      File('${staging.path}/$rel')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(gzip.decode(base64.decode(e.value as String)));
      staged.add(rel);
    }
  } catch (_) {
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    rethrow;
  }
  final root = Directory(dir);
  for (final e in root.listSync(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final rel = _relative(dir, e.path);
    if (!DeviceBackupPolicy.keepsFile(rel) || skipped.contains(rel)) continue;
    try {
      e.deleteSync();
    } catch (_) {}
  }
  for (final rel in staged) {
    final target = File('$dir/$rel');
    target.parent.createSync(recursive: true);
    final from = File('${staging.path}/$rel');
    try {
      from.renameSync(target.path);
    } on FileSystemException {
      from.copySync(target.path);
    }
  }
  if (staging.existsSync()) staging.deleteSync(recursive: true);
  return {'prefs': manifest['prefs'], 'secure': manifest['secure']};
}

String _relative(String dir, String path) {
  final base = dir.replaceAll('\\', '/');
  final p = path.replaceAll('\\', '/');
  final rel = p.startsWith(base) ? p.substring(base.length) : p;
  return rel.startsWith('/') ? rel.substring(1) : rel;
}
