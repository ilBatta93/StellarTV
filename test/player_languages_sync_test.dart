import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/models/player_settings.dart';
import 'package:stellar_tv/services/kids_pin_service.dart';
import 'package:stellar_tv/services/personal_vault.dart';
import 'package:stellar_tv/services/player_settings_service.dart';
import 'package:stellar_tv/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'languages and subtitle style reach every scope, engine stays',
    () async {
      final settings = PlayerSettingsService();
      final vod = await settings.load(scope: PlayerSettingsScope.filmSeriesTv);
      vod.preferredAudioLanguage = 'en';
      vod.subtitlesEnabled = true;
      vod.subtitleSize = SubtitleSize.values.last;
      final engine = vod.primaryEngine;
      await settings.save(vod, scope: PlayerSettingsScope.filmSeriesTv);
      final live = await settings.load(scope: PlayerSettingsScope.liveTv);
      expect(live.preferredAudioLanguage, 'en');
      expect(live.subtitlesEnabled, true);
      expect(live.subtitleSize, SubtitleSize.values.last);
      expect((await settings.load()).primaryEngine, engine);
    },
  );

  test('the shared choice passes the cloud filter and comes back', () async {
    final client = SupabaseClient(
      'https://example.invalid',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final remote = jsonEncode({
      'audio': 'ja',
      'subs': 'it',
      'on': true,
      'size': SubtitleSize.values.first.name,
      'color': SubtitleColor.values.last.name,
      'back': false,
      'bold': false,
    });
    final snapshot = PersonalVault.clean({
      'settings': {
        PlayerSettingsService.languagesKey: remote,
        'kids_pin': '4321',
      },
    });
    final cloud = Map<String, dynamic>.from(snapshot['settings']);
    expect(
      jsonDecode(cloud[PlayerSettingsService.languagesKey]),
      jsonDecode(remote),
    );
    await SyncService(client).applySnapshotSettings(cloud, overwrite: true);
    final s = await PlayerSettingsService().load();
    expect(s.preferredAudioLanguage, 'ja');
    expect(s.subtitleBackground, false);
    expect(s.subtitleColor, SubtitleColor.values.last);
    expect(await KidsPinService.get(), '4321');
    await client.dispose();
  });
}
