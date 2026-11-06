import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/providers/history_provider.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/services/sync_service.dart';
import 'package:stellar_tv/widgets/channel_card.dart';

Channel item(
  String id, {
  ContentType type = ContentType.movie,
  String? seriesKey,
  bool folder = false,
}) => Channel(
  id: id,
  name: 'Titolo $id',
  url: folder ? '' : 'https://example.invalid/$id',
  logo: '',
  group: 'Prova',
  type: type,
  seriesKey: seriesKey,
  isSeriesFolder: folder,
);

/// Catalog posters show the progress bar and the watched mark.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const runtime = Duration(minutes: 100);

  late SupabaseClient client;
  setUp(() {
    client = SupabaseClient(
      'https://example.invalid',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDown(() => client.dispose());

  test('films, episodes and series folders get their mark', () async {
    final history = HistoryProvider(SyncService(client));
    final movie = item('m1');
    expect(history.posterProgressFor(movie), isNull);

    await history.recordStart(movie);
    await history.updatePosition('m1', const Duration(minutes: 30), runtime);
    expect(
      history.posterProgressFor(movie),
      const PosterProgress(progress: 0.3, watched: false),
    );

    await history.updatePosition('m1', const Duration(minutes: 99), runtime);
    expect(history.posterProgressFor(movie)?.watched, isTrue);

    final episode = item('e1', type: ContentType.series, seriesKey: 's1');
    final folder = item(
      'f1',
      type: ContentType.series,
      seriesKey: 's1',
      folder: true,
    );
    await history.recordStart(episode);
    await history.updatePosition('e1', const Duration(minutes: 50), runtime);
    expect(history.posterProgressFor(folder)?.progress, closeTo(0.5, 1e-9));
    expect(history.posterProgressFor(folder)?.watched, isFalse);

    // A finished latest episode leaves the series folder without a mark.
    await history.updatePosition('e1', runtime, runtime);
    expect(history.posterProgressFor(folder), isNull);
    expect(history.posterProgressFor(episode)?.watched, isTrue);

    expect(
      history.posterProgressFor(item('l1', type: ContentType.live)),
      isNull,
    );
    history.dispose();
  });

  test('small playback steps do not change the mark', () {
    expect(
      const PosterProgress(progress: 0.301, watched: false),
      const PosterProgress(progress: 0.305, watched: false),
    );
    expect(
      const PosterProgress(progress: 0.3, watched: false),
      isNot(const PosterProgress(progress: 0.4, watched: false)),
    );
  });

  testWidgets('the card follows the progress option', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('stellartv/device'),
          (_) async => false,
        );
    await DeviceTypeService.initialize();
    final ui = UiSettings();
    await ui.load();
    final history = HistoryProvider(SyncService(client));
    final movie = item('m2');
    await history.recordStart(movie);
    await history.updatePosition('m2', runtime, runtime);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: ui),
          ChangeNotifierProvider.value(value: history),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 160,
                height: 300,
                child: ChannelCard(
                  channel: movie,
                  isFavorite: false,
                  onTap: () {},
                  onFavoriteTap: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await ui.setPosterProgress(false);
    await tester.pump();
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    history.dispose();
  });
}
