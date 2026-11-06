import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/banner_trailer.dart';
import 'package:stellar_tv/models/title_trailer.dart';
import 'package:stellar_tv/models/tmdb_item.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/services/image_warmup_service.dart';
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
    test('never on phones or low-memory TVs', () {
      bool allowed({
        BannerTrailerMode mode = BannerTrailerMode.background,
        bool isTv = true,
        bool lowRam = false,
      }) => bannerTrailerAllowed(mode: mode, isTv: isTv, lowRam: lowRam);
      expect(allowed(), isTrue);
      expect(allowed(mode: BannerTrailerMode.panel), isTrue);
      expect(allowed(mode: BannerTrailerMode.scene), isTrue);
      expect(allowed(mode: BannerTrailerMode.off), isFalse);
      expect(allowed(isTv: false), isFalse);
      expect(allowed(lowRam: true), isFalse);
      expect(BannerTrailerMode.scene.inScene, isTrue);
      expect(BannerTrailerMode.panel.inScene, isFalse);
    });

    test('the window is as tall as the banner, never too wide', () {
      final tall = trailerPanelSize(bannerWidth: 960, bannerHeight: 211);
      expect(tall.height, 191);
      expect(tall.width, closeTo(191 * 16 / 9, 1e-9));
      // A big banner: the width stops at the share, still 16:9.
      final big = trailerPanelSize(bannerWidth: 960, bannerHeight: 300);
      expect(big.width, closeTo(960 * 0.46, 1e-9));
      expect(big.width / big.height, closeTo(16 / 9, 1e-9));
      expect(trailerPanelSize(bannerWidth: 960, bannerHeight: 10).width, 0);
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
      expect(BannerTrailer.html(cover: false), contains('v+=step||8'));
    });

    test('unknown values fall back to safe defaults', () {
      expect(BannerTrailerModeInfo.parse('???'), BannerTrailerMode.off);
      expect(BannerTrailerAudioInfo.parse(null), BannerTrailerAudio.button);
      expect(parseBannerTrailerDelay(4), bannerTrailerDefaultDelay);
      expect(parseBannerTrailerDelay(8), 8);
    });

    test('the page starts muted and fades the sound in', () {
      final page = BannerTrailer.html(cover: true);
      expect(page, contains('function play(id,t)'));
      expect(page, contains('loadVideoById'));
      expect(page, contains('function release()'));
      expect(page, contains('cover=1'));
      expect(BannerTrailer.html(cover: false), contains('cover=0'));
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
      await ui.setBannerTrailer(BannerTrailerMode.scene);
      // The trailer in the scene picture turns the scene picture on.
      expect(ui.focusScene, isTrue);
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

  group('one player for every title', () {
    late List<_FakePage> pages;
    setUp(() {
      pages = [];
      BannerTrailer.lookup = (_, item) async =>
          TitleTrailer(key: 'video${item.id}', language: 'it');
      BannerTrailer.pageFactory = (onMessage) {
        final page = _FakePage(onMessage);
        pages.add(page);
        return page;
      };
    });
    tearDown(() {
      BannerTrailer.lookup = null;
      BannerTrailer.pageFactory = null;
    });

    final playing = <bool>[];
    Widget banner(TmdbItem? item, {bool visible = true}) => MaterialApp(
      home: TickerMode(
        enabled: visible,
        child: BannerTrailer(
          item: item,
          audio: BannerTrailerAudio.muted,
          delaySeconds: 3,
          onButton: ValueNotifier(false),
          onPlaying: playing.add,
        ),
      ),
    );

    Future<void> rest(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
    }

    testWidgets('a new title swaps the video in the same page', (tester) async {
      playing.clear();
      await tester.pumpWidget(banner(title(1)));
      await rest(tester);
      expect(pages, hasLength(1));
      final page = pages.single;
      // Asked before the page was ready: sent once it is.
      expect(page.scripts, isEmpty);
      page.send('ready');
      final first = page.lastPlay!;
      expect(first.video, 'video1');
      page.send('playing:${first.token}');
      await tester.pump();
      expect(playing, [true]);

      await tester.pumpWidget(banner(title(2)));
      expect(page.scripts.last, 'stop()');
      expect(playing, [true, false]);
      // A late event of the first title changes nothing.
      page.send('playing:${first.token}');
      await rest(tester);
      final second = page.lastPlay!;
      expect(second.video, 'video2');
      expect(second.token, isNot(first.token));
      page.send('playing:${second.token}');
      await tester.pump();
      expect(playing, [true, false, true]);
      // Back to the first title: it starts again, still the same page.
      await tester.pumpWidget(banner(title(1)));
      await rest(tester);
      expect(page.lastPlay!.video, 'video1');
      expect(pages, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      expect(page.disposed, isTrue);
    });

    testWidgets('leaving the Home frees the video, coming back restarts', (
      tester,
    ) async {
      await tester.pumpWidget(banner(title(5)));
      await rest(tester);
      final page = pages.single..send('ready');
      page.send('playing:${page.lastPlay!.token}');
      await tester.pumpWidget(banner(title(5), visible: false));
      expect(page.scripts.last, 'release()');
      await tester.pump(const Duration(seconds: 10));
      expect(page.plays, hasLength(1));
      await tester.pumpWidget(banner(title(5)));
      await rest(tester);
      expect(page.plays, hasLength(2));
      expect(page.lastPlay!.video, 'video5');
      expect(pages, hasLength(1));
    });

    testWidgets('memory pressure stops it; the next title plays', (
      tester,
    ) async {
      await tester.pumpWidget(banner(title(7)));
      await rest(tester);
      final page = pages.single..send('ready');
      page.send('playing:${page.lastPlay!.token}');
      TvImageMemoryGuard.trailerStops.value++;
      expect(page.scripts.last, 'release()');
      await tester.pump(const Duration(seconds: 10));
      // The same title does not start over by itself...
      expect(page.plays, hasLength(1));
      // ...the next one does.
      await tester.pumpWidget(banner(title(8)));
      await rest(tester);
      expect(page.lastPlay!.video, 'video8');
    });

    testWidgets('a player that never plays is rebuilt once', (tester) async {
      await tester.pumpWidget(banner(title(9)));
      await rest(tester);
      pages.single.send('ready');
      await tester.pump(const Duration(seconds: bannerTrailerWatchdogSeconds));
      expect(pages.first.disposed, isTrue);
      expect(pages, hasLength(2));
      pages.last.send('ready');
      expect(pages.last.lastPlay!.video, 'video9');
      // Still nothing: no endless retries.
      await tester.pump(const Duration(seconds: bannerTrailerWatchdogSeconds));
      expect(pages, hasLength(2));
      // The next title gets a fresh player.
      await tester.pumpWidget(banner(title(10)));
      await rest(tester);
      expect(pages, hasLength(3));
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

class _FakePage implements TrailerPage {
  _FakePage(this.onMessage);
  final void Function(String) onMessage;
  final scripts = <String>[];
  bool disposed = false;

  void send(String message) => onMessage(message);

  Iterable<({String video, int token})> get plays => scripts
      .map(RegExp(r"^play\('(.+)',(\d+)\)$").firstMatch)
      .whereType<RegExpMatch>()
      .map((m) => (video: m.group(1)!, token: int.parse(m.group(2)!)));

  ({String video, int token})? get lastPlay => plays.lastOrNull;

  @override
  void run(String script) => scripts.add(script);

  @override
  void dispose() => disposed = true;

  @override
  Widget build() => const SizedBox.expand();
}
