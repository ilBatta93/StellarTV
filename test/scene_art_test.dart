import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/tmdb_item.dart';
import 'package:stellar_tv/providers/history_provider.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/services/catalog_builder.dart';
import 'package:stellar_tv/services/catalog_rating_service.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/services/sync_service.dart';
import 'package:stellar_tv/widgets/catalog_layouts.dart';
import 'package:stellar_tv/widgets/channel_card.dart';

/// "Immagine di scena": Panoramica and In evidenza use the TMDB backdrop the
/// device already has, never one request per card.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SupabaseClient client;
  setUp(() {
    client = SupabaseClient(
      'https://example.invalid',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDown(() => client.dispose());

  Channel movie(String id, String name) => Channel(
    id: id,
    name: name,
    url: 'http://example.test/$id',
    logo: '',
    group: 'Film',
    type: ContentType.movie,
  );

  TmdbItem item(int id, {String? backdrop, String? poster}) =>
      TmdbItem.tryParse({
        'id': id,
        'media_type': 'movie',
        'title': 'Titolo $id',
        'backdrop_path': backdrop,
        'poster_path': poster,
      })!;

  test('scene url is the backdrop only, never the poster', () {
    expect(item(1, poster: '/p.jpg').sceneUrl, isNull);
    expect(
      item(1, backdrop: '/s.jpg').sceneUrl,
      'https://image.tmdb.org/t/p/w780/s.jpg',
    );
  });

  test('the shared cache brings the still with the identity', () {
    final c = movie('n', 'Titolo dal cloud');
    final full = CatalogRatingService.cloudIdentity(c, {
      'type': 'movie',
      'id': 42,
      'poster': '/p.jpg',
      'backdrop': '/s.jpg',
    }, 7.1);
    expect(full.key, 'movie_42');
    expect(full.sceneUrl, 'https://image.tmdb.org/t/p/w780/s.jpg');
    // Rows saved before the still column answer without it.
    final old = CatalogRatingService.cloudIdentity(c, {
      'type': 'movie',
      'id': 42,
      'poster': '/p.jpg',
    }, 7.1);
    expect(old.sceneUrl, isNull);
    expect(old.posterPath, '/p.jpg');
  });

  test('a later identity without still keeps the known one', () {
    final known = item(7, backdrop: '/s.jpg', poster: '/p.jpg');
    final cloud = item(7, poster: '/q.jpg');
    final kept = CatalogRatingService.keepScene(known, cloud);
    expect(kept.backdropPath, '/s.jpg');
    expect(kept.posterPath, '/q.jpg');
    // A different title replaces it: the old still would be wrong.
    expect(CatalogRatingService.keepScene(known, item(8)).backdropPath, isNull);
    expect(CatalogRatingService.keepScene(null, cloud), same(cloud));

    final c = movie('k', 'Titolo con scena');
    CatalogRatingService.instance.remember(c, known);
    CatalogRatingService.instance.remember(c, cloud);
    expect(CatalogScene.sceneOf(c), 'https://image.tmdb.org/t/p/w780/s.jpg');
  });

  for (final tv in [false, true]) {
    testWidgets('Panoramica shows the still only when on and known (tv: $tv)', (
      tester,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('stellartv/device'),
            (_) async => tv,
          );
      await DeviceTypeService.initialize();
      SharedPreferences.setMockInitialValues({});
      final ui = UiSettings();
      await ui.load();
      expect(ui.sceneArt, isFalse);
      final history = HistoryProvider(SyncService(client));
      final c = movie('p$tv', 'Titolo panoramico $tv');
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: ui),
            ChangeNotifierProvider.value(value: history),
          ],
          child: MaterialApp(
            home: Center(
              child: SizedBox(
                width: 320,
                height: 180,
                child: CatalogLandscapeCard(
                  entry: CatalogEntry(primary: c, variants: [c]),
                  isFavorite: false,
                  onTap: () {},
                  onFavoriteTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(CatalogSceneImage), findsNothing);
      expect(find.byType(CatalogArtwork), findsWidgets);

      // On, but no still on the device yet: the framed poster stays.
      await ui.setSceneArt(true);
      await tester.pump();
      expect(find.byType(CatalogSceneImage), findsNothing);
      expect(find.byType(CatalogArtwork), findsWidgets);

      // The still arrives (detail page opened): the card switches by itself.
      CatalogRatingService.instance.remember(c, item(50, backdrop: '/b.jpg'));
      // The store notifies once per burst, in a microtask.
      await tester.pump();
      await tester.pump();
      expect(find.byType(CatalogSceneImage), findsOneWidget);
      expect(find.byType(CatalogArtwork), findsNothing);
      expect(find.text('Titolo panoramico $tv'), findsOneWidget);

      await ui.setSceneArt(false);
      await tester.pump();
      expect(find.byType(CatalogSceneImage), findsNothing);
      expect(tester.takeException(), isNull);
      history.dispose();
    });

    testWidgets('In evidenza uses the still behind the poster (tv: $tv)', (
      tester,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('stellartv/device'),
            (_) async => tv,
          );
      await DeviceTypeService.initialize();
      SharedPreferences.setMockInitialValues({UiSettings.sceneArtKey: true});
      final ui = UiSettings();
      await ui.load();
      final c = movie('s$tv', 'Titolo in evidenza $tv');
      CatalogRatingService.instance.remember(c, item(60, backdrop: '/e.jpg'));
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: ui,
          child: MaterialApp(
            home: Scaffold(
              body: CatalogSpotlightHeader(
                entry: CatalogEntry(primary: c, variants: [c]),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(CatalogSceneImage), findsOneWidget);
      // The poster stays in front of the still.
      expect(find.byType(CatalogArtwork), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
