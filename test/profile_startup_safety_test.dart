import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/models/user_profile.dart';
import 'package:stellar_tv/providers/profile_provider.dart';
import 'package:stellar_tv/services/profile_service.dart';
import 'package:stellar_tv/services/sync_service.dart';

class OfflineProfiles extends ProfileService {
  OfflineProfiles(super.client);
  @override
  Future<String?> getSelectedProfileId() async => 'kids';
  @override
  Future<List<UserProfile>> listProfiles(String code) async =>
      throw StateError('offline');
}

class LocalSync extends SyncService {
  LocalSync(super.client);
  @override
  Future<String?> getStoredCode() async => 'test';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Offline unresolved Kids selection never announces adult or deselection',
    () async {
      SharedPreferences.setMockInitialValues({
        'kids_profile_ids': ['kids'],
      });
      final client = SupabaseClient('https://example.test', 'test');
      final service = OfflineProfiles(client);
      expect(await ProfileProvider.savedSelectionIsKids(service), isTrue);
      final provider = ProfileProvider(service, LocalSync(client));
      var announcements = 0;
      provider.onSelectionChanged = (_) => announcements++;
      await provider.load();
      expect(provider.selectedId, 'kids');
      expect(announcements, 0);
      expect(await ProfileProvider.savedSelectionIsKids(service), isTrue);
      provider.dispose();
      await client.dispose();
    },
  );
}
