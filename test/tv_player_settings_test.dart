import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/player_settings.dart';
import 'package:stellar_tv/services/player_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'TV scopes inherit legacy settings and remain independently persisted',
    () async {
      final legacy = PlayerSettings()..startTimeoutSeconds = 23;
      SharedPreferences.setMockInitialValues({
        'player_settings_v1': jsonEncode(legacy.toJson()),
      });
      final service = PlayerSettingsService();
      final live = await service.load(scope: PlayerSettingsScope.liveTv);
      final vod = await service.load(scope: PlayerSettingsScope.filmSeriesTv);
      expect(live.startTimeoutSeconds, 23);
      expect(vod.startTimeoutSeconds, 23);
      live.primaryEngine = PlayerEngineType.exo;
      live.startTimeoutSeconds = 9;
      await service.save(live, scope: PlayerSettingsScope.liveTv);
      expect(
        (await PlayerSettingsService().load(
          scope: PlayerSettingsScope.liveTv,
        )).primaryEngine,
        PlayerEngineType.exo,
      );
      expect(
        (await service.load(
          scope: PlayerSettingsScope.filmSeriesTv,
        )).startTimeoutSeconds,
        23,
      );
      expect((await service.load()).startTimeoutSeconds, 23);
      await service.reset(scope: PlayerSettingsScope.filmSeriesTv);
      expect(
        (await service.load(
          scope: PlayerSettingsScope.filmSeriesTv,
        )).startTimeoutSeconds,
        PlayerSettings().startTimeoutSeconds,
      );
      expect(
        (await service.load(
          scope: PlayerSettingsScope.liveTv,
        )).startTimeoutSeconds,
        9,
      );
      expect((await service.load()).startTimeoutSeconds, 23);
    },
  );
  test(
    'First TV load creates a snapshot, not an ongoing mobile fallback',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = PlayerSettingsService();
      final tv = await service.load(scope: PlayerSettingsScope.liveTv);
      await service.save(PlayerSettings()..startTimeoutSeconds = 28);
      expect(
        (await service.load(
          scope: PlayerSettingsScope.liveTv,
        )).startTimeoutSeconds,
        tv.startTimeoutSeconds,
      );
    },
  );
}
