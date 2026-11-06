import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/episode_metadata.dart';
import 'package:stellar_tv/models/focus_scene_policy.dart';
import 'package:stellar_tv/models/tmdb_item.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/services/focus_scene_service.dart';
import 'package:stellar_tv/services/personal_vault.dart';
import 'package:stellar_tv/widgets/focus_scene_card.dart';
import 'package:stellar_tv/widgets/poster_card.dart';
import 'package:stellar_tv/widgets/section_row.dart';
import 'package:stellar_tv/widgets/tv_focusable.dart';

/// "Scena sulla locandina selezionata": the cover the remote rests on
/// turns into a scene still (episode still for series) with its details.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TmdbItem title(int id, {bool movie = true}) => TmdbItem.tryParse({
    'id': id,
    'media_type': movie ? 'movie' : 'tv',
    if (movie) 'title': 'Titolo $id' else 'name': 'Titolo $id',
    'backdrop_path': '/b$id.jpg',
    'poster_path': '/p$id.jpg',
    'release_date': '2019-05-01',
    'vote_average': 7.5,
  })!;

  EpisodeMetadata episode(int season, int number) => EpisodeMetadata(
    seriesId: 1,
    season: season,
    episode: number,
    title: 'Episodio $number',
    overview: '',
    stillPath: '/s${season}e$number.jpg',
  );

  group('which picture', () {
    test('a film always shows its scene', () {
      expect(focusSceneEpisode(series: false), isNull);
      expect(
        focusSceneEpisode(series: false, last: (season: 2, episode: 3)),
        isNull,
      );
    });

    test('a series not started shows its first episode', () {
      expect(focusSceneEpisode(series: true), (season: 1, episode: 1));
    });

    test('a series in progress shows the episode being watched', () {
      expect(focusSceneEpisode(series: true, last: (season: 2, episode: 4)), (
        season: 2,
        episode: 4,
      ));
    });

    test('after a finished episode, the next one', () {
      const last = (season: 2, episode: 4);
      expect(focusSceneEpisode(series: true, last: last, lastWatched: true), (
        season: 2,
        episode: 5,
      ));
      expect(focusSceneFallback(last: last, lastWatched: true), (
        season: 3,
        episode: 1,
      ));
      expect(focusSceneFallback(last: last), isNull);
    });

    test('episode label', () {
      expect(focusSceneEpisodeLabel(2, 5, 'Il ritorno'), 'S2 E5 · Il ritorno');
      expect(focusSceneEpisodeLabel(1, 1, ' '), 'S1 E1');
      expect(focusSceneEpisodeLabel(1, 1, null), 'S1 E1');
    });
  });

  group('service', () {
    test('a film needs no request', () async {
      var asked = 0;
      final service = FocusSceneService(
        loadEpisode: (_, _, _) async {
          asked++;
          return null;
        },
      );
      final scene = await service.resolve(title(1));
      expect(scene.imageUrl, title(1).sceneUrl);
      expect(scene.episode, isNull);
      expect(asked, 0);
    });

    test('a series not started: first episode still, asked once', () async {
      final asked = <String>[];
      final service = FocusSceneService(
        loadEpisode: (_, s, e) async {
          asked.add('$s:$e');
          return episode(s, e);
        },
      );
      final series = title(2, movie: false);
      final scene = await service.resolve(series);
      await service.resolve(series);
      expect(scene.episode?.episode, 1);
      expect(scene.imageUrl, episode(1, 1).stillUrl);
      expect(asked, ['1:1']);
    });

    test('season finished: first episode of the next season', () async {
      final service = FocusSceneService(
        loadEpisode: (_, s, e) async => s == 2 && e == 1 ? episode(2, 1) : null,
      );
      final scene = await service.resolve(
        title(3, movie: false),
        last: (season: 1, episode: 10),
        lastWatched: true,
      );
      expect(scene.episode?.season, 2);
      expect(scene.imageUrl, episode(2, 1).stillUrl);
    });

    test('nothing left to watch: the series still', () async {
      final service = FocusSceneService(loadEpisode: (_, _, _) async => null);
      final series = title(4, movie: false);
      final scene = await service.resolve(
        series,
        last: (season: 3, episode: 8),
        lastWatched: true,
      );
      expect(scene.episode, isNull);
      expect(scene.imageUrl, series.sceneUrl);
    });

    test('offline: the series still', () async {
      final service = FocusSceneService(
        loadEpisode: (_, _, _) async => throw Exception('offline'),
      );
      final series = title(5, movie: false);
      expect((await service.resolve(series)).imageUrl, series.sceneUrl);
    });
  });

  group('settings', () {
    test('off by default, details on, all saved and synced', () async {
      SharedPreferences.setMockInitialValues({});
      final ui = UiSettings();
      await ui.load();
      expect(ui.focusScene, isFalse);
      expect(ui.focusSceneLogo, isTrue);
      expect(ui.focusSceneDetails, isTrue);
      expect(ui.focusSceneEpisode, isTrue);
      expect(ui.focusSceneBadges, isTrue);
      final before = ui.signature;
      await ui.setFocusScene(true);
      await ui.setFocusSceneLogo(false);
      await ui.setFocusSceneBadges(false);
      expect(ui.signature, isNot(before));
      final again = UiSettings();
      await again.load();
      expect(again.focusScene, isTrue);
      expect(again.focusSceneLogo, isFalse);
      expect(again.focusSceneBadges, isFalse);
      expect(again.focusSceneDetails, isTrue);
      await again.resetAppearance();
      expect(again.focusScene, isFalse);
      expect(again.focusSceneLogo, isTrue);
      for (final key in [
        UiSettings.focusSceneKey,
        UiSettings.focusSceneLogoKey,
        UiSettings.focusSceneDetailsKey,
        UiSettings.focusSceneEpisodeKey,
        UiSettings.focusSceneBadgesKey,
      ]) {
        expect(PersonalVault.settingKeys, contains(key));
      }
    });
  });

  group('on TV', () {
    Future<void> device({required bool tv}) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('stellartv/device'),
            (call) async => call.method == 'isTv' ? tv : null,
          );
      await DeviceTypeService.initialize();
    }

    tearDown(() => device(tv: false));

    Future<UiSettings> settings({required bool on}) async {
      SharedPreferences.setMockInitialValues({UiSettings.focusSceneKey: on});
      final ui = UiSettings();
      await ui.load();
      return ui;
    }

    Widget row(UiSettings ui, List<TmdbItem> items) =>
        ChangeNotifierProvider.value(
          value: ui,
          child: MaterialApp(
            home: Scaffold(
              body: HorizontalRow(
                height: 260,
                itemCount: items.length,
                itemBuilder: (_, i) =>
                    TmdbPosterCard(item: items[i], onTap: () {}),
              ),
            ),
          ),
        );

    void focusCard(WidgetTester tester, int index) {
      final inner = find.descendant(
        of: find.byType(TvFocusable).at(index),
        matching: find.byType(ExcludeFocus),
      );
      Focus.of(tester.element(inner.first)).requestFocus();
    }

    double width(WidgetTester tester, int index) =>
        tester.getSize(find.byType(TmdbPosterCard).at(index)).width;

    Future<void> settle(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    }

    testWidgets('the rested cover widens into a scene, then back', (
      tester,
    ) async {
      await device(tv: true);
      final ui = await settings(on: true);
      final items = [title(11), title(12), title(13)];
      await tester.pumpWidget(row(ui, items));
      final poster = width(tester, 0);
      focusCard(tester, 0);
      await tester.pump();
      // Passing through: still a poster, nothing loaded.
      await tester.pump(const Duration(milliseconds: 300));
      expect(width(tester, 0), poster);
      expect(find.byType(FocusSceneArt), findsNothing);
      // Resting on it.
      await tester.pump(FocusSceneHost.delay);
      await tester.pump();
      expect(find.byType(FocusSceneArt), findsOneWidget);
      final height = poster * 3 / 2;
      expect(width(tester, 0), closeTo(height * 16 / 9, 0.5));
      expect(find.text('Titolo 11'), findsWidgets);
      // Moving on shrinks it back.
      focusCard(tester, 1);
      // One frame delivers the focus change, the next one lays it out.
      await tester.pump();
      await tester.pump();
      expect(width(tester, 0), poster);
      expect(find.byType(FocusSceneArt), findsNothing);
      await settle(tester);
    });

    testWidgets('switched off, covers stay posters', (tester) async {
      await device(tv: true);
      final ui = await settings(on: false);
      await tester.pumpWidget(row(ui, [title(21), title(22)]));
      final poster = width(tester, 0);
      focusCard(tester, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(width(tester, 0), poster);
      expect(find.byType(FocusSceneArt), findsNothing);
      await settle(tester);
    });

    testWidgets('chosen details are hidden when switched off', (tester) async {
      await device(tv: true);
      final ui = await settings(on: true);
      await ui.setFocusSceneDetails(false);
      await ui.setFocusSceneLogo(false);
      await tester.pumpWidget(row(ui, [title(31)]));
      focusCard(tester, 0);
      await tester.pump(
        FocusSceneHost.delay + const Duration(milliseconds: 50),
      );
      await tester.pump();
      expect(find.byType(FocusSceneArt), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(FocusSceneArt),
          matching: find.byType(RatingBadge),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(FocusSceneArt),
          matching: find.text('Titolo 31'),
        ),
        findsOneWidget,
      );
      await settle(tester);
    });
  });
}
