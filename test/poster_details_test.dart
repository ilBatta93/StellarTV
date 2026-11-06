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
import 'package:stellar_tv/screens/catalog_page.dart';
import 'package:stellar_tv/services/catalog_rating_service.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/services/sync_service.dart';
import 'package:stellar_tv/services/title_runtime_store.dart';
import 'package:stellar_tv/widgets/channel_card.dart';

/// "Anno e durata sotto il titolo": year from the catalog, length learned
/// from title pages, never one request per poster.
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

  Channel movie(String id, String name, {int release = 0}) => Channel(
    id: id,
    name: name,
    url: 'http://example.test/$id',
    logo: '',
    group: 'Film',
    type: ContentType.movie,
    releaseDate: release,
  );

  TmdbItem item(int id, {String type = 'movie', String date = ''}) =>
      TmdbItem.tryParse({
        'id': id,
        'media_type': type,
        'title': 'Titolo $id',
        'release_date': date,
      })!;

  test('label joins what is known', () {
    expect(posterDetailsLabel(year: 2019, minutes: 107), '2019 · 1 h 47 min');
    expect(
      posterDetailsLabel(year: 2021, minutes: 52, series: true),
      '2021 · ep. 52 min',
    );
    expect(posterDetailsLabel(year: 2019), '2019');
    expect(posterDetailsLabel(minutes: 90), '1 h 30 min');
    expect(posterDetailsLabel(), '');
  });

  test('year from the provider, the name, then the stored identity', () {
    expect(posterYearOf(movie('a', 'Titolo', release: 20190521)), 2019);
    expect(posterYearOf(movie('b', 'Titolo (2004)')), 2004);
    final unknown = movie('c', 'Titolo senza anno');
    expect(posterYearOf(unknown), isNull);
    CatalogRatingService.instance.remember(
      unknown,
      item(9001, date: '1999-03-31'),
    );
    expect(posterYearOf(unknown), 1999);
  });

  test('length is learned once and read back without network', () {
    final c = movie('d', 'Altro titolo');
    final identity = item(9002);
    CatalogRatingService.instance.remember(c, identity);
    expect(TitleRuntimeStore.instance.minutesOf(c), isNull);
    TitleRuntimeStore.instance.remember(identity, 0);
    expect(TitleRuntimeStore.instance.minutesOf(c), isNull);
    TitleRuntimeStore.instance.remember(identity, 118);
    expect(TitleRuntimeStore.instance.minutesOf(c), 118);
  });

  for (final tv in [false, true]) {
    test(
      'the extra line makes the cell taller, same columns (tv: $tv)',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('stellartv/device'),
              (_) async => tv,
            );
        await DeviceTypeService.initialize();
        for (final compact in [false, true]) {
          final plain = channelGridDelegate(
            ContentType.movie,
            compact: compact,
          );
          final details = channelGridDelegate(
            ContentType.movie,
            compact: compact,
            showDetails: true,
          );
          expect(details.childAspectRatio, lessThan(plain.childAspectRatio));
          expect(details.maxCrossAxisExtent, plain.maxCrossAxisExtent);
        }
      },
    );
  }

  testWidgets('the card shows the line only when the option is on', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('stellartv/device'),
          (_) async => false,
        );
    await DeviceTypeService.initialize();
    SharedPreferences.setMockInitialValues({});
    final ui = UiSettings();
    await ui.load();
    final history = HistoryProvider(SyncService(client));
    final c = movie('e', 'Con anno', release: 20120101);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: ui),
          ChangeNotifierProvider.value(value: history),
        ],
        child: MaterialApp(
          home: Center(
            child: SizedBox(
              width: 140,
              height: 260,
              child: ChannelCard(
                channel: c,
                isFavorite: false,
                onTap: () {},
                onFavoriteTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(PosterDetailsLine), findsNothing);
    await ui.setPosterDetails(true);
    await tester.pump();
    expect(find.byType(PosterDetailsLine), findsOneWidget);
    expect(find.text('2012'), findsOneWidget);
    expect(tester.takeException(), isNull);
    history.dispose();
  });
}
