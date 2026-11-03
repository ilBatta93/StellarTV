import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/track_languages_policy.dart';
import 'package:stellar_tv/services/title_tracks_service.dart';

void main() {
  group('trackLanguageCode', () {
    test('tags of two and three letters', () {
      expect(trackLanguageCode('ita', ''), 'it');
      expect(trackLanguageCode('en-US', ''), 'en');
      expect(trackLanguageCode('ger', ''), 'de');
      expect(trackLanguageCode('sv', ''), 'sv');
    });

    test('a language word in the label when the tag is missing', () {
      expect(trackLanguageCode(null, 'Italiano 5.1'), 'it');
      expect(trackLanguageCode('und', 'English (SDH)'), 'en');
      expect(trackLanguageCode(null, 'Traccia 2'), 'und');
    });
  });

  test('codes keep order, unknown tracks count once each', () {
    expect(
      trackLanguageCodes(const [
        ('ita', ''),
        ('it', 'Italiano commento'),
        ('eng', ''),
        (null, 'Traccia 3'),
        (null, 'Traccia 4'),
      ]),
      ['it', 'en', 'und', 'und'],
    );
  });

  group('mergeTitleTracks', () {
    test('a series shows the languages of any episode', () {
      final merged = mergeTitleTracks(const [
        TitleTracks(audio: ['it'], subtitles: ['it'], seenDay: 3),
        TitleTracks(audio: ['it', 'en'], subtitles: [], seenDay: 5),
      ]);
      expect(merged.audio, ['it', 'en']);
      expect(merged.subtitles, ['it']);
      expect(merged.seenDay, 5);
      expect(merged.alternateAudio, isTrue);
    });

    test('single untagged tracks do not look like alternate audio', () {
      final merged = mergeTitleTracks(const [
        TitleTracks(audio: ['und']),
        TitleTracks(audio: ['und']),
      ]);
      expect(merged.alternateAudio, isFalse);
    });

    test('an episode with two untagged tracks still counts', () {
      final merged = mergeTitleTracks(const [
        TitleTracks(audio: ['und']),
        TitleTracks(audio: ['und', 'und']),
      ]);
      expect(merged.alternateAudio, isTrue);
    });
  });

  test('labels put unknown tracks last', () {
    expect(languagesLabel(const ['it', 'en']), 'IT · EN');
    expect(languagesLabel(const ['it', 'und']), 'IT · altra');
    expect(languagesLabel(const ['und', 'und']), '2 altre');
  });

  test('old or broken stored entries read safely', () {
    final t = TitleTracks.fromJson(const {
      'a': ['it', 3, ''],
      's': 'x',
    });
    expect(t.audio, ['it']);
    expect(t.subtitles, isEmpty);
    expect(t.seenDay, 0);
  });

  group('TitleTracksService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      TitleTracksService.instance.resetForTest();
    });

    test('records survive a reload and stay on the device', () async {
      final service = TitleTracksService.instance;
      await service.record('movie_1', audio: ['it', 'en'], subtitles: ['it']);
      service.resetForTest();
      await service.ensureLoaded();
      expect(service.of('movie_1').audio, ['it', 'en']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'title_tracks_v1'});
    });

    test('an engine that cannot list subtitles keeps the last list', () async {
      final service = TitleTracksService.instance;
      await service.record('episode_2', audio: ['it'], subtitles: ['en']);
      await service.record('episode_2', audio: ['it', 'en']);
      expect(service.of('episode_2').subtitles, ['en']);
      expect(service.of('episode_2').audio, ['it', 'en']);
    });

    test('nothing known, nothing stored', () async {
      final service = TitleTracksService.instance;
      await service.record('movie_3', audio: const []);
      expect(service.of('movie_3').isEmpty, isTrue);
    });
  });
}
