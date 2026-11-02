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
    'legacy vault merge drops all players but preserves Home preferences',
    () {
      final merged = PersonalVault.merge(
        {
          'settings': {
            'player_settings_v1': '{"volume":0.5}',
            'player_settings_tv_live_v1': '{"engine":"exo"}',
            'player_settings_tv_vod_v1': '{"codec":"auto"}',
            'ui_home_shape': 'square',
            'ui_scale': 110,
          },
        },
        {
          'settings': {'ui_home_recent_limit': 30},
        },
      );
      expect(merged['settings'], {
        'ui_home_shape': 'square',
        'ui_scale': 110,
        'ui_home_recent_limit': 30,
      });
    },
  );
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
  test('v2 envelopes are compressed and round-trip', () async {
    final history = {
      for (var i = 0; i < 500; i++)
        'movie:$i': {
          'id': 'movie:$i',
          'type': 'movie',
          'title': 'Sample title number $i',
          'pos': i,
          'dur': 5400,
          'watched': DateTime.utc(
            2026,
            1,
            1,
          ).add(Duration(minutes: i)).toIso8601String(),
        },
    };
    final payload = {'history': history};
    final envelope = await PersonalVault.encrypt(payload, key, 'account-a');
    expect(envelope['v'], 2);
    final plainSize = utf8
        .encode(jsonEncode(PersonalVault.clean(payload)))
        .length;
    final cipherSize = base64Decode(envelope['ciphertext'] as String).length;
    expect(cipherSize, lessThan(plainSize ~/ 4));
    final back = await PersonalVault.decrypt(envelope, key, 'account-a');
    expect((back['history'] as Map).length, 500);
    expect(back['history']['movie:7']['pos'], 7);
  });
  test('a v2 envelope relabelled as v1 is rejected', () async {
    final envelope = await PersonalVault.encrypt({}, key, 'account-a');
    await expectLater(
      PersonalVault.decrypt({...envelope, 'v': 1}, key, 'account-a'),
      throwsA(anything),
    );
  });
  test('decrypts the synthetic website v2 fixture', () async {
    final envelope = jsonDecode(
      await File('test/fixtures/web_vault_v2.json').readAsString(),
    );
    expect(envelope['v'], 2);
    final result = await PersonalVault.decrypt(
      envelope,
      key,
      'fixture-account',
    );
    expect(result['history']['sample']['pos'], 37);
    expect(result['favorite_ids'], ['sample']);
  });
  test('reactions travel in their own lane and come back intact', () {
    final device = {
      'p1': {
        'movie_7': {
          'vote': 1,
          'at': '2026-11-02T10:00:00.000Z',
          'item': {
            'id': 7,
            'media_type': 'movie',
            'title': 'Sample',
            'poster_path': '/abc.jpg',
            'stellar_vote_policy': 1,
          },
        },
        'tv_9': {'vote': 0, 'at': '2026-11-02T11:00:00.000Z', 'item': {}},
      },
    };
    final lane = PersonalVault.reactionsToLane(device);
    expect(lane.keys, containsAll(['p1|movie_7', 'p1|tv_9']));
    final merged = PersonalVault.merge({}, {
      'profile_histories': {PersonalVault.reactionsLane: lane},
    });
    final back = PersonalVault.laneToReactions(
      merged['profile_histories'][PersonalVault.reactionsLane],
    );
    expect(back['p1']['movie_7']['vote'], 1);
    expect(back['p1']['movie_7']['item']['poster_path'], '/abc.jpg');
    expect(back['p1']['tv_9']['vote'], 0);
  });
  test('the reactions lane is not capped like a history', () {
    final lane = {
      for (var i = 0; i < 600; i++)
        'p|movie_$i': {
          'id': i,
          'media_type': 'movie',
          'vote': 1,
          'watched': '2026-11-02T10:00:00.000Z',
        },
    };
    final merged = PersonalVault.merge({}, {
      'profile_histories': {PersonalVault.reactionsLane: lane},
    });
    expect(
      (merged['profile_histories'][PersonalVault.reactionsLane] as Map).length,
      600,
    );
  });
  test('image paths are kept only as relative TMDB file names', () {
    final clean = PersonalVault.clean({
      'tmdb_favorites': [
        {
          'id': 1,
          'media_type': 'movie',
          'poster_path': '/abc.jpg',
          'backdrop_path': 'https://x.test/a.jpg',
        },
        {'id': 2, 'media_type': 'tv', 'poster_path': '../etc/passwd'},
      ],
    });
    final items = clean['tmdb_favorites'] as List;
    expect(items[0]['poster_path'], '/abc.jpg');
    expect(items[0].containsKey('backdrop_path'), isFalse);
    expect(items[1].containsKey('poster_path'), isFalse);
  });
  test('the adult content switch stays on the device', () {
    final clean = PersonalVault.clean({
      'settings': {'show_adult_content': true, 'theme_mode': 'dark'},
    });
    expect(clean['settings'], {'theme_mode': 'dark'});
  });
}
