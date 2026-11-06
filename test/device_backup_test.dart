import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/device_backup_policy.dart';
import 'package:stellar_tv/services/backup_transfer.dart';
import 'package:stellar_tv/services/device_backup.dart';
import 'package:stellar_tv/services/key_handoff.dart';

void main() {
  final fixture = jsonDecode(
    File('test/fixtures/backup_transfer.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  group('backup transfer (twin of the site backupTransfer.ts)', () {
    test('seals exactly like the shared fixture, both directions', () async {
      final payload = KeyHandoff.fromB64u(fixture['payload'] as String);
      for (final direction in ['restore', 'save']) {
        final f = fixture[direction] as Map<String, dynamic>;
        final sealed = await BackupTransfer.seal(
          fixture['receiver'] as String,
          f['code'] as String,
          direction,
          payload,
          senderSeed: List.filled(32, fixture['senderSeed'] as int),
          nonce: List.filled(12, fixture['nonceByte'] as int),
        );
        expect(sealed, f['sealed']);
      }
    });

    test('opens the site package and refuses tampering', () async {
      final tv = await X25519().newKeyPairFromSeed(
        List.filled(32, fixture['receiverSeed'] as int),
      );
      final sealed = (fixture['restore'] as Map)['sealed'] as String;
      final plain = await BackupTransfer.open(tv, 'ABC234', 'restore', sealed);
      expect(utf8.decode(plain), 'StellarTV backup fixture ✓');
      await expectLater(
        BackupTransfer.open(tv, 'ABC235', 'restore', sealed),
        throwsA(anything),
      );
      await expectLater(
        BackupTransfer.open(tv, 'ABC234', 'save', sealed),
        throwsA(anything),
      );
    });

    test('splits into parts that join back', () {
      final text = 'a' * (BackupTransfer.partChars * 2 + 5);
      final parts = BackupTransfer.split(text);
      expect(parts.map((p) => p.length), [
        BackupTransfer.partChars,
        BackupTransfer.partChars,
        5,
      ]);
      expect(parts.join(), text);
    });
  });

  group('backup policy', () {
    test('keeps settings, never the session, downloads or sync markers', () {
      expect(DeviceBackupPolicy.keepsPref('ui_accent'), isTrue);
      expect(DeviceBackupPolicy.keepsPref('xtream_server'), isTrue);
      expect(DeviceBackupPolicy.keepsPref('kids_pin'), isTrue);
      expect(DeviceBackupPolicy.keepsPref('sb-abc-auth-token'), isFalse);
      expect(DeviceBackupPolicy.keepsPref('offline_downloads_v1'), isFalse);
      expect(DeviceBackupPolicy.keepsPref('sync_last_saved_snapshot'), isFalse);
      expect(DeviceBackupPolicy.keepsPref('sync_code'), isFalse);
    });

    test('keeps support files but not videos, partial writes or escapes', () {
      expect(DeviceBackupPolicy.keepsFile('json_cache/awards_v1.json'), isTrue);
      expect(DeviceBackupPolicy.keepsFile('tv_ratings_v3.json'), isTrue);
      expect(DeviceBackupPolicy.keepsFile('downloads/a.mp4'), isFalse);
      expect(DeviceBackupPolicy.keepsFile('x.json.tmp'), isFalse);
      expect(DeviceBackupPolicy.keepsFile('../prefs.xml'), isFalse);
      expect(DeviceBackupPolicy.keepsFile('/etc/hosts'), isFalse);
    });

    test('preference values survive the round trip', () {
      for (final v in <Object>[
        'testo',
        true,
        42,
        1.5,
        <String>['a', 'b'],
      ]) {
        final encoded = jsonDecode(
          jsonEncode(DeviceBackupPolicy.encodePref(v)),
        );
        expect(DeviceBackupPolicy.decodePref(encoded), v);
      }
      expect(DeviceBackupPolicy.decodePref(['i', 'x']), isNull);
      expect(DeviceBackupPolicy.decodePref('x'), isNull);
    });
  });

  group('backup files', () {
    late Directory from, to;
    setUp(() {
      from = Directory.systemTemp.createTempSync('stv_backup_from');
      to = Directory.systemTemp.createTempSync('stv_backup_to');
    });
    tearDown(() {
      from.deleteSync(recursive: true);
      to.deleteSync(recursive: true);
    });

    test('restores every kept file and replaces the old ones', () {
      File('${from.path}/json_cache/a.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"a":1}');
      File('${from.path}/catalog.ndjson').writeAsStringSync('riga\n' * 1000);
      File('${from.path}/downloads/video.mp4')
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(64, 1));
      File('${to.path}/old_cache.json').writeAsStringSync('vecchio');
      File('${to.path}/downloads/mine.mp4')
        ..createSync(recursive: true)
        ..writeAsStringSync('mio');

      final bytes = buildBackup(
        from.path,
        {'created': '2026-11-06T20:00:00.000Z', 'app': '1', 'tv': true},
        {
          'ui_accent': ['s', 'blu'],
        },
        {
          'vault': {'personal_vault_x': 'chiave'},
        },
      );
      final summary = DeviceBackupSummary.fromManifest(
        decodeManifest(Uint8List.fromList(bytes)),
      )!;
      expect(summary.files, 2);
      expect(summary.prefs, 1);
      expect(summary.secrets, 1);
      expect(summary.tv, isTrue);

      final data = restoreFiles(to.path, bytes);
      expect(
        File('${to.path}/json_cache/a.json').readAsStringSync(),
        '{"a":1}',
      );
      expect(
        File('${to.path}/catalog.ndjson').readAsStringSync(),
        'riga\n' * 1000,
      );
      expect(File('${to.path}/old_cache.json').existsSync(), isFalse);
      expect(File('${to.path}/downloads/mine.mp4').existsSync(), isTrue);
      expect(File('${to.path}/downloads/video.mp4').existsSync(), isFalse);
      expect((data['prefs'] as Map)['ui_accent'], ['s', 'blu']);
      expect(
        ((data['secure'] as Map)['vault'] as Map)['personal_vault_x'],
        'chiave',
      );
    });

    test('a damaged file leaves the device untouched', () {
      File('${from.path}/a.json').writeAsStringSync('nuovo');
      File('${to.path}/a.json').writeAsStringSync('vecchio');
      final good = buildBackup(from.path, {}, {}, {});
      final manifest =
          decodeManifest(Uint8List.fromList(good)) as Map<String, dynamic>;
      (manifest['files'] as Map)['b.json'] = 'non-base64!';
      final bad = Uint8List.fromList(
        gzip.encode(utf8.encode(jsonEncode(manifest))),
      );
      expect(() => restoreFiles(to.path, bad), throwsA(anything));
      expect(File('${to.path}/a.json').readAsStringSync(), 'vecchio');
      expect(Directory('${to.path}/.restore_staging').existsSync(), isFalse);
    });

    test('refuses something that is not a backup', () {
      final bytes = Uint8List.fromList(
        gzip.encode(utf8.encode(jsonEncode({'format': 'altro'}))),
      );
      expect(() => restoreFiles(to.path, bytes), throwsFormatException);
    });
  });
}
