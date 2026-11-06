import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/banner_trailer.dart';
import 'package:stellar_tv/models/title_trailer.dart';
import 'package:stellar_tv/models/tmdb_item.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/services/personal_vault.dart';
import 'package:stellar_tv/widgets/banner_trailer.dart';

/// "Trailer nel banner" of the TV Home.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TmdbItem title(int id) => TmdbItem.tryParse({
    'id': id,
    'media_type': 'movie',
    'title': 'Titolo $id',
  })!;

  group('policy', () {
    test('never on phones, low-memory TVs or under memory pressure', () {
      bool allowed({
        BannerTrailerMode mode = BannerTrailerMode.background,
        bool isTv = true,
        bool lowRam = false,
        bool pressure = false,
      }) => bannerTrailerAllowed(
        mode: mode,
        isTv: isTv,
        lowRam: lowRam,
        memoryPressure: pressure,
      );
      expect(allowed(), isTrue);
      expect(allowed(mode: BannerTrailerMode.panel), isTrue);
      expect(allowed(mode: BannerTrailerMode.off), isFalse);
      expect(allowed(isTv: false), isFalse);
      expect(allowed(lowRam: true), isFalse);
      expect(allowed(pressure: true), isFalse);
    });

    test('sound follows the chosen audio mode', () {
      bool audible(
        BannerTrailerAudio audio, {
        int seconds = 0,
        bool onButton = false,
      }) => bannerTrailerAudible(
        audio: audio,
        playedFor: Duration(seconds: seconds),
        onButton: onButton,
      );
      expect(audible(BannerTrailerAudio.muted, seconds: 60), isFalse);
      expect(audible(BannerTrailerAudio.muted, onButton: true), isFalse);
      expect(audible(BannerTrailerAudio.delayed, seconds: 2), isFalse);
      expect(
        audible(BannerTrailerAudio.delayed, seconds: bannerAudioDelaySeconds),
        isTrue,
      );
      expect(audible(BannerTrailerAudio.delayed, onButton: true), isTrue);
      expect(audible(BannerTrailerAudio.button, seconds: 60), isFalse);
      expect(audible(BannerTrailerAudio.button, onButton: true), isTrue);
      expect(audible(BannerTrailerAudio.together, seconds: 0), isTrue);
      expect(
        bannerAudioFadeStep(BannerTrailerAudio.together),
        lessThan(bannerAudioFadeStep(BannerTrailerAudio.button)),
      );
      expect(
        BannerTrailerAudioInfo.parse('together'),
        BannerTrailerAudio.together,
      );
      expect(BannerTrailer.html('abc'), contains('v+=step||8'));
    });

    test('unknown values fall back to safe defaults', () {
      expect(BannerTrailerModeInfo.parse('???'), BannerTrailerMode.off);
      expect(BannerTrailerAudioInfo.parse(null), BannerTrailerAudio.button);
      expect(parseBannerTrailerDelay(4), bannerTrailerDefaultDelay);
      expect(parseBannerTrailerDelay(8), 8);
    });

    test('the page starts muted and fades the sound in', () {
      final page = BannerTrailer.html('abcdefghijk');
      expect(page, contains("videoId:'abcdefghijk'"));
      expect(page, contains('mute:1'));
      expect(page, contains('function audio(on,step)'));
      expect(page, contains('youtube-nocookie.com'));
    });
  });

  group('settings', () {
    test('off by default, saved, synced and reset', () async {
      SharedPreferences.setMockInitialValues({});
      final ui = UiSettings();
      await ui.load();
      expect(ui.bannerTrailer, BannerTrailerMode.off);
      expect(ui.bannerTrailerAudio, BannerTrailerAudio.button);
      expect(ui.bannerTrailerDelay, bannerTrailerDefaultDelay);
      final before = ui.signature;
      await ui.setBannerTrailer(BannerTrailerMode.panel);
      await ui.setBannerTrailerAudio(BannerTrailerAudio.delayed);
      await ui.setBannerTrailerDelay(3);
      expect(ui.signature, isNot(before));
      final again = UiSettings();
      await again.load();
      expect(again.bannerTrailer, BannerTrailerMode.panel);
      expect(again.bannerTrailerAudio, BannerTrailerAudio.delayed);
      expect(again.bannerTrailerDelay, 3);
      await again.resetAppearance();
      expect(again.bannerTrailer, BannerTrailerMode.off);
      for (final key in [
        UiSettings.bannerTrailerKey,
        UiSettings.bannerTrailerAudioKey,
        UiSettings.bannerTrailerDelayKey,
      ]) {
        expect(PersonalVault.settingKeys, contains(key));
      }
    });
  });

  group('timing', () {
    final asked = <String>[];
    setUp(() {
      asked.clear();
      BannerTrailer.lookup = (_, item) async {
        asked.add(item.key);
        // No trailer: nothing else is built, no web player in tests.
        return null;
      };
    });
    tearDown(() => BannerTrailer.lookup = null);

    Widget banner(TmdbItem? item) => MaterialApp(
      home: BannerTrailer(
        item: item,
        audio: BannerTrailerAudio.button,
        delaySeconds: 3,
        onButton: ValueNotifier(false),
      ),
    );

    testWidgets('asks only after resting on the same title', (tester) async {
      await tester.pumpWidget(banner(title(1)));
      await tester.pump(const Duration(seconds: 2));
      // Moving on before the delay: the first title is never looked up.
      await tester.pumpWidget(banner(title(2)));
      await tester.pump(const Duration(seconds: 2));
      expect(asked, isEmpty);
      await tester.pump(const Duration(seconds: 2));
      expect(asked, ['movie_2']);
      // Same title again: no second request.
      await tester.pumpWidget(banner(title(2)));
      await tester.pump(const Duration(seconds: 5));
      expect(asked, ['movie_2']);
    });

    testWidgets('a covered Home does not start a trailer', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TickerMode(
            enabled: false,
            child: BannerTrailer(
              item: title(3),
              audio: BannerTrailerAudio.muted,
              delaySeconds: 3,
              onButton: ValueNotifier(false),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 10));
      expect(asked, isEmpty);
    });

    testWidgets('no title, nothing', (tester) async {
      await tester.pumpWidget(banner(null));
      await tester.pump(const Duration(seconds: 10));
      expect(asked, isEmpty);
      expect(find.byType(SizedBox), findsWidgets);
    });
  });

  test('a trailer key is validated before use', () {
    final picked = TitleTrailer.select({
      'results': [
        {
          'site': 'YouTube',
          'type': 'Trailer',
          'iso_639_1': 'it',
          'key': 'abcdefghijk',
        },
      ],
    }, 'it');
    expect(picked?.key, 'abcdefghijk');
    expect(kIsWeb, isFalse);
  });
}
