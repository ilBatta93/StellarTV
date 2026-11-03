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

/// Episodes offer "Apri con …" like films, by remote and by touch.
void main() {
  Future<List<bool>> pumpCard(WidgetTester tester, {required bool tv}) async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('stellartv/device'),
          (_) async => tv,
        );
    await DeviceTypeService.initialize();
    await ExternalPlayerService.instance.setPlayer(
      const ExternalPlayer(package: 'org.videolan.vlc', label: 'VLC'),
    );
    final played = <bool>[];
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
                onPlayWith: played.add,
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
    await tester.tap(find.byTooltip('Apri con VLC'));
    await tester.pump();
    expect(played, [true]);
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
    await tester.pump();
    expect(played, [true]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
