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
    final clamped = validSegments(
      const EpisodeSegments(
        outro: SkipSegment(
          'outro',
          Duration(seconds: 800),
          Duration(seconds: 910),
        ),
      ),
      const Duration(seconds: 900),
    );
    expect(clamped.outro?.end, const Duration(seconds: 900));
    expect(
      validSegments(
        const EpisodeSegments(
          intro: SkipSegment('intro', Duration.zero, Duration(seconds: 40)),
        ),
        Duration.zero,
      ).intro?.end,
      const Duration(seconds: 40),
    );
  });
  test('a weak match is ignored and a recap stays separate from the intro', () {
    final parsed = IntroDbService.parse({
      'intro': {'start_sec': 30, 'end_sec': 90, 'confidence': 0.2},
      'recap': {'start_sec': 0, 'end_sec': 28, 'confidence': 0.9},
    });
    expect(parsed.intro, null);
    expect(parsed.all.single.type, 'recap');
    final glued = validSegments(
      IntroDbService.parse({
        'recap': {'start_sec': 0, 'end_sec': 20},
        'intro': {'start_sec': 21, 'end_sec': 80},
      }),
      const Duration(minutes: 40),
    );
    final choice = activeSkip(glued, const Duration(seconds: 5));
    expect(choice?.label, 'Salta sigla');
    expect(choice?.target, const Duration(seconds: 80));
  });
  test('chapters of this file win and opening credits are recognized', () {
    final local = chapterSegments([
      {'title': 'Opening Credits', 'time': 12},
      {'title': 'Story', 'time': 70},
      {'title': 'End credits', 'time': 550},
    ], const Duration(seconds: 600));
    expect(local.intro?.start, const Duration(seconds: 12));
    final remote = validSegments(
      const EpisodeSegments(
        intro: SkipSegment('intro', Duration(seconds: 90), Duration(seconds: 140)),
        all: [
          SkipSegment('intro', Duration(seconds: 90), Duration(seconds: 140)),
        ],
      ),
      const Duration(seconds: 600),
    );
    expect(mergeSkipSegments(remote, local).intro?.start, const Duration(seconds: 12));
    final scene = postCreditsSkip(
      validSegments(
        const EpisodeSegments(
          outro: SkipSegment('outro', Duration(seconds: 500), Duration(seconds: 600)),
          all: [
            SkipSegment('outro', Duration(seconds: 500), Duration(seconds: 600)),
            SkipSegment('post_credits', Duration(seconds: 560), Duration(seconds: 590)),
          ],
        ),
        const Duration(seconds: 600),
      ),
      const Duration(seconds: 520),
    );
    expect(scene?.target, const Duration(seconds: 560));
    expect(scene?.label, 'Salta titoli');
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
