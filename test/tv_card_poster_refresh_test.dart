import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/tmdb_item.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/services/catalog_rating_service.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/services/title_facet_index.dart';
import 'package:stellar_tv/services/title_matching.dart';
import 'package:stellar_tv/widgets/channel_card.dart';
import 'package:stellar_tv/widgets/poster_card.dart';
import 'package:stellar_tv/widgets/title_facets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const device = MethodChannel('stellartv/device');

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          device,
          (call) async => call.method == 'isTv',
        );
    await DeviceTypeService.initialize();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(device, (call) async => false);
    await DeviceTypeService.initialize();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(device, null);
  });

  testWidgets('TV card shows a TMDB poster that arrives after the rating', (
    tester,
  ) async {
    final channel = Channel(
      id: 'poster-later',
      name: 'Titolo Senza Locandina',
      url: '',
      logo: '',
      group: 'Prova',
      type: ContentType.movie,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => UiSettings(),
        child: MaterialApp(
          home: SizedBox(
            width: 200,
            height: 340,
            child: ChannelCard(
              channel: channel,
              isFavorite: false,
              onTap: () {},
              onFavoriteTap: () {},
            ),
          ),
        ),
      ),
    );
    String? posterUrl() =>
        tester.widget<PosterImage>(find.byType(PosterImage).first).url;
    expect(posterUrl(), isNull);

    const item = TmdbItem(
      id: 7,
      mediaType: 'movie',
      title: 'Titolo Senza Locandina',
      overview: '',
      posterPath: '/poster.jpg',
      backdropPath: null,
      voteAverage: 0,
      popularity: 0,
      releaseDate: '',
    );
    final service = CatalogRatingService.instance;
    service.identities.put(
      parseTitle(channel.displaySeriesName).key('movie'),
      item,
    );
    // The rating is unchanged (still unknown); only the poster is new.
    service.notifyListeners();
    await tester.pump();

    expect(posterUrl(), item.posterUrl);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a rating badge stays still when other titles change', (
    tester,
  ) async {
    final channel = Channel(
      id: 'badge-still',
      name: 'Titolo Fermo',
      url: '',
      logo: '',
      group: 'Prova',
      type: ContentType.movie,
    );
    await tester.pumpWidget(
      MaterialApp(home: Center(child: ChannelRatingBadge(channel))),
    );
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    // The index notifies for every title it touches.
    TitleFacetIndex.instance.notifyListeners();
    CatalogRatingService.instance.notifyListeners();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
