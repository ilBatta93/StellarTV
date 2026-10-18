import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/services/personal_vault.dart';
import 'package:stellar_tv/services/favorites_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key =
      'STV1-000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F';
  test(
    'separate 256-bit recovery key round trips without source fields',
    () async {
      final raw = {
        'history': {
          'item': {
            'id': 'item',
            'title': 'Sample',
            'url': 'https://private.example/u/p',
            'watched': '2026-10-18T12:00:00Z',
            'pos': 10,
          },
        },
        'settings': {'xtream_password': 'private', 'ui_catalog_view': 'grid'},
      };
      final envelope = await PersonalVault.encrypt(raw, key, 'account');
      expect(jsonEncode(envelope), isNot(contains('Sample')));
      expect(jsonEncode(envelope), isNot(contains('private')));
      final decoded = await PersonalVault.decrypt(envelope, key, 'account');
      expect(decoded['history']['item']['pos'], 10);
      expect(decoded['history']['item'].containsKey('url'), false);
      expect(decoded['settings'], {'ui_catalog_view': 'grid'});
    },
  );
  test('wrong recovery key and wrong account cannot decrypt', () async {
    final e = await PersonalVault.encrypt({}, key, 'account');
    await expectLater(
      PersonalVault.decrypt(e, PersonalVault.generateKey(), 'account'),
      throwsA(anything),
    );
    await expectLater(
      PersonalVault.decrypt(e, key, 'other'),
      throwsA(anything),
    );
  });
  test('fresh nonces and authenticated tamper rejection', () async {
    final a = await PersonalVault.encrypt({}, key, 'account'),
        b = await PersonalVault.encrypt({}, key, 'account');
    expect(a['nonce'], isNot(b['nonce']));
    final data = base64Decode(a['ciphertext'] as String);
    data[0] ^= 1;
    a['ciphertext'] = base64Encode(data);
    await expectLater(
      PersonalVault.decrypt(a, key, 'account'),
      throwsA(anything),
    );
  });
  test(
    'newest real timestamp wins across time zones and deletion wins ties',
    () {
      final merged = PersonalVault.mergeHistory(
        {
          'x': {'watched': '2026-10-18T14:00:00+02:00', 'pos': 1},
        },
        {
          'x': {'watched': '2026-10-18T12:01:00Z', 'pos': 2},
        },
      );
      expect(merged['x']['pos'], 2);
      expect(
        PersonalVault.mergeHistory({
          'x': {'watched': '2026-10-18T12:01:00Z', 'deleted': true},
        }, merged)['x']['deleted'],
        true,
      );
    },
  );
  test('favorite removals survive stale devices, newer re-add wins', () {
    final old = {
      'favorite_ids': ['x'],
      'profile_histories': {
        PersonalVault.favoriteLane: {
          'c:x': {'deleted': false, 'watched': '2026-10-18T10:00:00Z'},
        },
      },
    };
    final removed = {
      'profile_histories': {
        PersonalVault.favoriteLane: {
          'c:x': {'deleted': true, 'watched': '2026-10-18T12:00:00Z'},
        },
      },
    };
    expect(PersonalVault.merge(old, removed)['favorite_ids'], isEmpty);
    expect(PersonalVault.merge(removed, old)['favorite_ids'], isEmpty);
    final added = {
      'profile_histories': {
        PersonalVault.favoriteLane: {
          'c:x': {'deleted': false, 'watched': '2026-10-18T13:00:00Z'},
        },
      },
    };
    expect(PersonalVault.merge(removed, added)['favorite_ids'], ['x']);
  });
  test(
    'decrypted removals apply without deleting unrelated local favorites',
    () async {
      SharedPreferences.setMockInitialValues({
        'favorite_channels': ['x', 'local'],
      });
      await FavoritesService().applyEncrypted({
        'favorite_ids': [],
        'profile_histories': {
          PersonalVault.favoriteLane: {
            'c:x': {'deleted': true, 'watched': '2026-10-18T12:00:00Z'},
          },
        },
      });
      expect(await FavoritesService().getFavoriteIds(), {'local'});
    },
  );
  test(
    'recovery generation uses exactly 32 bytes and never accepts password',
    () {
      expect(PersonalVault.keyBytes(PersonalVault.generateKey()).length, 32);
      expect(() => PersonalVault.keyBytes('password'), throwsFormatException);
    },
  );
  test('concurrent favorite events preserve every removal marker', () async {
    SharedPreferences.setMockInitialValues({});
    final service = FavoritesService();
    await Future.wait([
      service.recordEvent('c:a', true),
      service.recordEvent('c:b', true),
    ]);
    final prefs = await SharedPreferences.getInstance();
    final events = jsonDecode(
      prefs.getString('vault_favorite_events_v1') ?? '{}',
    );
    expect(events['c:a']['deleted'], true);
    expect(events['c:b']['deleted'], true);
  });
  test('decrypts the synthetic website AES-256-GCM fixture', () async {
    final envelope = jsonDecode(
      await File('test/fixtures/web_vault.json').readAsString(),
    );
    final result = await PersonalVault.decrypt(
      envelope,
      key,
      'fixture-account',
    );
    expect(result['history']['sample']['pos'], 37);
    expect(result['favorite_ids'], ['sample']);
  });
}
