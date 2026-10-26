import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/player_settings.dart';
import 'package:stellar_tv/player/mediakit_engine.dart';
import 'package:stellar_tv/services/device_type_service.dart';
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
  test('legacy cache sliders become the buffer mpv already used', () {
    const mib = 1024 * 1024;
    expect(
      PlayerSettings.migrateCacheBytes(1500, live: true, tv: true),
      16 * mib,
    );
    expect(
      PlayerSettings.migrateCacheBytes(5000, live: false, tv: true),
      48 * mib,
    );
    expect(
      PlayerSettings.migrateCacheBytes(1500, live: true, tv: false),
      64 * mib,
    );
    expect(
      PlayerSettings.migrateCacheBytes(40 * mib, live: true, tv: true),
      40 * mib,
    );
    expect(
      PlayerSettings.migrateCacheBytes(8 * mib, live: false, tv: false),
      32 * mib,
    );
    final legacy = PlayerSettings()
      ..liveCachingMs = 1500
      ..networkCachingMs = 5000;
    expect(
      MediaKitEngine.cacheBytes(legacy, isLive: true, tv: true),
      16 * mib,
    );
    expect(
      MediaKitEngine.cacheBytes(legacy, isLive: false, tv: true, preview: true),
      8 * mib,
    );
    expect(
      MediaKitEngine.streamLavfOptions(reconnect: false, live: true),
      'reconnect=0',
    );
    expect(
      MediaKitEngine.streamLavfOptions(reconnect: true, live: true),
      contains('reconnect_at_eof=1'),
    );
    expect(
      MediaKitEngine.streamLavfOptions(reconnect: true, live: false),
      contains('reconnect_streamed=1'),
    );
    final old = PlayerSettings.fromJson({
      'engineV': 2,
      'skipFrames': true,
      'httpReconnect': false,
      'audioPassthrough': true,
    });
    expect(old.skipFrames, isFalse);
    expect(old.httpReconnect, isFalse);
    expect(old.audioPassthrough, isTrue);
    expect(PlayerEngineType.mediakit.supportsReconnect, isTrue);
    expect(PlayerEngineType.exo.supportsReconnect, isFalse);
    expect(PlayerEngineType.mediakit.supportsSkipFrames, isTrue);
    expect(PlayerEngineType.exo.supportsSkipFrames, isFalse);
    expect(PlayerEngineType.mediakit.supportsAudioPassthrough, isTrue);
    expect(PlayerEngineType.exo.supportsAudioPassthrough, isFalse);
    expect(PlayerEngineType.exo.supportsCacheBuffer, isFalse);
    expect(PlayerEngineType.mediakit.supportsBackBuffer, isFalse);
  });

  test('TV live migrates once from the previous engine to mpv', () async {
    await _setTelevision(true);
    addTearDown(() => _setTelevision(false));
    final previous = PlayerSettings()
      ..primaryEngine = PlayerEngineType.exo
      ..autoFallback = false
      ..startTimeoutSeconds = 11;
    final stored = previous.toJson()..['liveEngineV'] = 5;
    SharedPreferences.setMockInitialValues({
      'player_settings_tv_live_v1': jsonEncode(stored),
    });
    final service = PlayerSettingsService();
    final live = await service.load(scope: PlayerSettingsScope.liveTv);
    expect(live.primaryEngine, PlayerEngineType.mediakit);
    expect(live.autoFallback, isTrue);
    expect(live.startTimeoutSeconds, 11);
    final again = await service.load(scope: PlayerSettingsScope.liveTv);
    expect(again.primaryEngine, PlayerEngineType.mediakit);

    final chosen = PlayerSettings()..primaryEngine = PlayerEngineType.exo;
    SharedPreferences.setMockInitialValues({
      'player_settings_tv_live_v1': jsonEncode(chosen.toJson()),
    });
    expect(
      (await PlayerSettingsService().load(
        scope: PlayerSettingsScope.liveTv,
      )).primaryEngine,
      PlayerEngineType.exo,
    );
    expect(chosen.toJson()['liveEngineV'], 6);
  });
}

Future<void> _setTelevision(bool television) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('stellartv/device'), (
        call,
      ) async {
        if (call.method == 'isTv') return television;
        if (call.method == 'isFireTv') return false;
        return null;
      });
  await DeviceTypeService.initialize();
  debugDefaultTargetPlatformOverride = null;
}
