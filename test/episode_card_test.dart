import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/series_details.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/widgets/episode_card.dart';

void main() {
  testWidgets('Horizontal episodes fit TV and D-pad selects the next episode', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('stellartv/device'),
          (_) async => true,
        );
    await DeviceTypeService.initialize();
    debugDefaultTargetPlatformOverride = null;
    var played = -1;
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => UiSettings(),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 320,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 4,
                separatorBuilder: (_, _) => const SizedBox(width: 20),
                itemBuilder: (_, i) => EpisodeCard(
                  episode: SeriesEpisode(
                    channel: Channel(
                      id: '$i',
                      name: 'Episode $i',
                      url: '',
                      logo: '',
                      group: '',
                      type: ContentType.series,
                    ),
                    season: 1,
                    number: i + 1,
                    title: 'Long episode title',
                  ),
                  onPlay: () => played = i,
                  onToggleWatched: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    FocusManager.instance.primaryFocus?.nextFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select, platform: 'android');
    await tester.pump();
    expect(played, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select, platform: 'android');
    await tester.pump();
    expect(played, 1);
    expect(tester.takeException(), isNull);
  });
}
