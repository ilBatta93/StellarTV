import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/services/personal_vault.dart';
import 'package:stellar_tv/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  setUp(
    () => client = SupabaseClient(
      'https://example.invalid',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    ),
  );

  tearDown(() => SyncService.deviceClass = () => 'touch');

  test('layout settings leave the device under its class', () async {
    SyncService.deviceClass = () => 'tv';
    SharedPreferences.setMockInitialValues({
      'ui_home_density': 'dense',
      'ui_accent': 'blu',
    });
    final payload = await SyncService(client).collectSnapshot();
    expect(payload.settings['ui_home_density@tv'], 'dense');
    expect(payload.settings.containsKey('ui_home_density'), false);
    expect(payload.settings['ui_accent'], 'blu');
    final cloud = PersonalVault.clean(payload.toJson())['settings'] as Map;
    expect(cloud['ui_home_density@tv'], 'dense');
  });

  test('a phone takes its own layout, not the TV one', () async {
    SyncService.deviceClass = () => 'touch';
    SharedPreferences.setMockInitialValues({});
    await SyncService(client).applySnapshotSettings({
      'ui_home_density': 'balanced',
      'ui_home_density@tv': 'dense',
      'ui_home_density@touch': 'compact',
      'ui_accent': 'blu',
    }, overwrite: true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ui_home_density'), 'compact');
    expect(prefs.getString('ui_accent'), 'blu');
    expect(prefs.getString('ui_home_density@tv'), isNull);
  });

  test('without its own value a class starts from the shared one', () {
    final seen = PersonalVault.settingsFromVault({
      'ui_grid_size': 'large',
      'ui_grid_size@tv': 'small',
    }, 'touch');
    expect(seen['ui_grid_size'], 'large');
    expect(seen.keys.where((k) => k.contains('@')), isEmpty);
  });

  test('only layout keys and known classes pass the vault filter', () {
    expect(PersonalVault.isVaultSettingKey('ui_scale@touch'), true);
    expect(PersonalVault.isVaultSettingKey('ui_accent@tv'), false);
    expect(PersonalVault.isVaultSettingKey('ui_scale@car'), false);
    expect(PersonalVault.isVaultSettingKey('xtream_password@tv'), false);
  });
}
