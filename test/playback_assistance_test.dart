import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/player_settings.dart';
import 'package:stellar_tv/services/player_settings_service.dart';
import 'package:stellar_tv/services/playback_assistance.dart';
import 'package:stellar_tv/services/introdb_service.dart';
import 'package:stellar_tv/services/provider_diagnosis.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('autoplay defaults on for existing installations', () {
    expect(PlayerSettings.fromJson({}).autoNextEpisode, true);
  });
  test(
    'autoplay off is shared by VOD scopes and leaves live settings independent',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = PlayerSettingsService();
      final settings = PlayerSettings()..autoNextEpisode = false;
      await service.save(settings, scope: PlayerSettingsScope.filmSeriesTv);
      expect(
        (await service.load(scope: PlayerSettingsScope.filmSeriesTv))
            .autoNextEpisode,
        false,
      );
      expect((await service.load()).autoNextEpisode, false);
      expect(
        (await service.load(scope: PlayerSettingsScope.liveTv)).autoNextEpisode,
        false,
      );
    },
  );
  test('lookup removes technical labels but preserves title and year', () {
    expect(
      segmentLookupTitle('IT: Dark (2017) FHD S01E02 HEVC'),
      'Dark (2017)',
    );
    expect(segmentLookupTitle('The IT Crowd'), 'The IT Crowd');
  });
  test('invalid or out-of-runtime skips are rejected', () {
    expect(
      IntroDbService.parse({
        'intro': {'start_sec': -1, 'end_sec': 50},
      }).intro,
      null,
    );
    expect(
      IntroDbService.parse({
        'intro': {'start_sec': 1, 'end_sec': double.infinity},
      }).intro,
      null,
    );
    expect(
      validSegments(
        const EpisodeSegments(
          intro: SkipSegment(
            'intro',
            Duration(seconds: 10),
            Duration(seconds: 1000),
          ),
        ),
        const Duration(seconds: 900),
      ).intro,
      null,
    );
  });
  test('only explicit bounded local chapters become skips', () {
    final s = chapterSegments([
      {'title': 'Intro', 'time': 0},
      {'title': 'Main', 'time': 60},
      {'title': 'End credits', 'time': 550},
    ], const Duration(seconds: 600));
    expect(s.intro?.end, const Duration(seconds: 60));
    expect(s.outro?.start, const Duration(seconds: 550));
    expect(
      chapterSegments([
        {'title': 'Chapter 1', 'time': 0},
      ], const Duration(seconds: 600)).intro,
      null,
    );
  });
  test('fallback suggests only final 90 seconds of a known long runtime', () {
    expect(
      suggestNext(
        position: const Duration(seconds: 509),
        duration: const Duration(seconds: 600),
      ),
      false,
    );
    expect(
      suggestNext(
        position: const Duration(seconds: 510),
        duration: const Duration(seconds: 600),
      ),
      true,
    );
    expect(
      suggestNext(
        position: const Duration(seconds: 200),
        duration: const Duration(seconds: 250),
      ),
      false,
    );
    expect(
      suggestNext(position: Duration.zero, duration: Duration.zero),
      false,
    );
  });
  test('connection limit is evidence not proof of a second device', () {
    expect(
      classifyProvider(200, {
        'user_info': {
          'status': 'Active',
          'active_cons': '1',
          'max_connections': '1',
        },
      }).condition,
      ProviderCondition.limit,
    );
    expect(
      classifyProvider(200, {
        'user_info': {
          'status': 'Active',
          'active_cons': '1',
          'max_connections': '0',
        },
      }).condition,
      ProviderCondition.online,
    );
  });
  test('inactive account differs from reachable server', () {
    expect(
      classifyProvider(200, {
        'user_info': {'status': 'Expired'},
      }).condition,
      ProviderCondition.inactive,
    );
    expect(
      classifyProvider(200, {
        'user_info': {
          'status': 'Active',
          'active_cons': '0',
          'max_connections': '1',
        },
      }, playbackFailed: true).condition,
      ProviderCondition.online,
    );
  });
  test(
    'server errors and unverifiable answers do not claim account diagnosis',
    () {
      expect(
        classifyProvider(503, null).condition,
        ProviderCondition.unreachable,
      );
      expect(
        classifyProvider(403, null).condition,
        ProviderCondition.unauthorized,
      );
      expect(
        classifyProvider(200, '<html>error</html>').condition,
        ProviderCondition.unknown,
      );
      expect(
        classifyProvider(200, {'user_info': {}}).condition,
        ProviderCondition.unknown,
      );
    },
  );
}
