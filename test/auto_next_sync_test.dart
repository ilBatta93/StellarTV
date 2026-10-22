import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/services/player_settings_service.dart';
import 'package:stellar_tv/services/sync_service.dart';
import 'package:stellar_tv/services/personal_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('automatic next migrates the old false choice and shares it across VOD scopes', () async {
    SharedPreferences.setMockInitialValues({
      'player_settings_tv_vod_v1': jsonEncode({'autoNextEpisode': false}),
    });
    final settings = PlayerSettingsService();
    expect(
      (await settings.load(scope: PlayerSettingsScope.filmSeriesTv))
          .autoNextEpisode,
      false,
    );
    expect((await settings.load()).autoNextEpisode, false);
    await settings.setAutoNextEpisode(true);
    expect(
      (await settings.load(scope: PlayerSettingsScope.filmSeriesTv))
          .autoNextEpisode,
      true,
    );
    await settings.setAutoNextEpisode(false);
    final live = await settings.load(scope: PlayerSettingsScope.liveTv);
    live.autoNextEpisode = true;
    await settings.save(live, scope: PlayerSettingsScope.liveTv);
    expect((await settings.load()).autoNextEpisode, false);
  });
  test('cloud restore false reaches the VOD player without restoring technical settings', () async {
    final client = SupabaseClient(
      'https://example.invalid',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final sync = SyncService(client);
    final settings = PlayerSettingsService();
    await settings.setAutoNextEpisode(true);
    expect(SyncService.isSyncedKey('ui_auto_next_episode'), true);
    expect(SyncService.isSyncedKey('player_settings_v1'), false);
    final snapshot = PersonalVault.clean({
      'settings': {'ui_auto_next_episode': false, 'player_settings_v1': '{}'},
    });
    expect(snapshot['settings'], {'ui_auto_next_episode': false});
    await sync.applySnapshotSettings(
      Map<String, dynamic>.from(snapshot['settings']),
      overwrite: true,
    );
    expect((await settings.load()).autoNextEpisode, false);
    expect(
      (await settings.load(scope: PlayerSettingsScope.filmSeriesTv))
          .autoNextEpisode,
      false,
    );
    await client.dispose();
  });
}
