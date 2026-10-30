import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const deviceKey = 'sb-project-auth-token';
  setUp(
    () => SharedPreferences.setMockInitialValues({
      deviceKey: 'this-device-only',
      'sync_code': 'account',
    }),
  );

  test(
    'snapshot never uploads SDK token and never overwrites it on restore',
    () async {
      final client = SupabaseClient('https://example.test', 'test');
      final sync = SyncService(client);
      final snapshot = await sync.collectSnapshot();
      expect(snapshot.settings.containsKey(deviceKey), isFalse);
      await sync.applySnapshotSettings({
        deviceKey: 'other-device-token',
        'supabase.auth.token': 'legacy-other-token',
        'xtream_username': 'updated-list',
      }, overwrite: true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(deviceKey), 'this-device-only');
      expect(prefs.containsKey('supabase.auth.token'), isFalse);
      expect(prefs.getString('xtream_username'), isNull);
      await client.dispose();
    },
  );

  test(
    'signed out startup does not spend eight seconds waiting for a new login',
    () async {
      final client = SupabaseClient('https://example.test', 'test');
      expect(
        await SyncService(client)
            .waitForSession()
            .timeout(const Duration(milliseconds: 500)),
        isFalse,
      );
      await client.dispose();
    },
  );
}
