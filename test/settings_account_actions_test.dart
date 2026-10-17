import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/xtream_edit.dart';
import 'package:stellar_tv/services/settings_logout.dart';

void main() {
  test('Invalid Xtream credentials leave device and cloud unchanged', () async {
    final calls = <String>[];
    final result = await saveXtreamEdit(
      authenticate: () async => false,
      persist: () async {
        calls.add('write');
      },
      sync: () async {
        calls.add('cloud');
        return true;
      },
      reload: () async {
        calls.add('reload');
      },
    );
    expect(result.saved, false);
    expect(calls, isEmpty);
  });
  test(
    'Verified URL username and password reach cloud before catalog reload',
    () async {
      final stored = <String, String>{
        'server': 'http://old.test',
        'username': 'old',
        'password': 'old',
      };
      Map<String, String>? cloud;
      final calls = <String>[];
      final result = await saveXtreamEdit(
        authenticate: () async {
          calls.add('verify');
          return true;
        },
        persist: () async {
          calls.add('write');
          stored.addAll({
            'server': 'https://new.test',
            'username': 'new-user',
            'password': 'new-password',
          });
        },
        sync: () async {
          calls.add('cloud');
          cloud = Map.of(stored);
          return true;
        },
        reload: () async {
          calls.add('reload');
        },
      );
      expect(result.saved, true);
      expect(result.synced, true);
      expect(calls, ['verify', 'write', 'cloud', 'reload']);
      expect(cloud, {
        'server': 'https://new.test',
        'username': 'new-user',
        'password': 'new-password',
      });
    },
  );
  test(
    'Failed cloud sync is reported without losing validated device list',
    () async {
      var reloaded = false;
      final result = await saveXtreamEdit(
        authenticate: () async => true,
        persist: () async {},
        sync: () async => throw Exception('offline'),
        reload: () async {
          reloaded = true;
        },
      );
      expect(result.saved, true);
      expect(result.synced, false);
      expect(reloaded, true);
    },
  );
  test(
    'Logout completes local cleanup even when account cleanup fails',
    () async {
      final calls = <String>[];
      await expectLater(
        logoutFromSettings(
          signOut: () async {
            throw StateError('failure');
          },
          resetGuest: () async {
            calls.add('guest');
          },
          clearPlaylist: () async {
            calls.add('playlist');
          },
        ),
        throwsStateError,
      );
      expect(calls, ['guest', 'playlist']);
    },
  );
  test(
    'Logout clears saved session and guest mode before playlist removal',
    () async {
      var signedIn = true;
      var guest = true;
      var playlist = true;
      final calls = <String>[];
      await logoutFromSettings(
        signOut: () async {
          signedIn = false;
          calls.add('account');
        },
        resetGuest: () async {
          guest = false;
          calls.add('guest');
        },
        clearPlaylist: () async {
          playlist = false;
          calls.add('playlist');
        },
      );
      expect(calls, ['account', 'guest', 'playlist']);
      expect(signedIn, false);
      expect(guest, false);
      expect(playlist, false);
    },
  );
}
