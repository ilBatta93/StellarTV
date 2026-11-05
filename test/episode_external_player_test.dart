import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/series_details.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/services/external_player_service.dart';
import 'package:stellar_tv/widgets/episode_card.dart';

/// Episodes offer "Apri con …" like films, by remote and by touch. Every
/// press asks which app to use and stores nothing.
void main() {
  Future<List<String?>> pumpCard(
    WidgetTester tester, {
    required bool tv,
  }) async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('stellartv/device'),
          (_) async => tv,
        );
    await DeviceTypeService.initialize();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('stellartv/player'), (
          call,
        ) async {
          if (call.method != 'externalPlayers') return null;
          return [
            {'package': 'org.videolan.vlc', 'label': 'VLC'},
            {'package': 'com.brouken.player', 'label': 'Just Player'},
          ];
        });
    final played = <String?>[];
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => UiSettings(),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: EpisodeCard(
                episode: SeriesEpisode(
                  channel: Channel(
                    id: 'ep1',
                    name: 'Episode 1',
                    url: 'https://example.invalid/ep1.mp4',
                    logo: '',
                    group: '',
                    type: ContentType.series,
                  ),
                  season: 1,
                  number: 1,
                  title: 'Pilot',
                ),
                onPlay: () {},
                onToggleWatched: () {},
                onPlayWith: (app) => played.add(app?.package),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return played;
  }

  testWidgets('touch: the episode opens in the external player', (
    tester,
  ) async {
    final played = await pumpCard(tester, tv: false);
    await tester.tap(find.byTooltip('Apri con…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Just Player'));
    await tester.pumpAndSettle();
    expect(played, ['com.brouken.player']);
    // The pick is one-off: nothing becomes the saved player.
    expect(ExternalPlayerService.instance.player, isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('remote: Down then Right reaches the external player button', (
    tester,
  ) async {
    final played = await pumpCard(tester, tv: true);
    FocusManager.instance.primaryFocus?.nextFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'episode-download:ep1',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'episode-external:ep1',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'episode-watched:ep1',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select, platform: 'android');
    await tester.pumpAndSettle();
    expect(find.text('Apri con'), findsOneWidget);
    await tester.tap(find.text('VLC'));
    await tester.pumpAndSettle();
    expect(played, ['org.videolan.vlc']);
    expect(ExternalPlayerService.instance.player, isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
