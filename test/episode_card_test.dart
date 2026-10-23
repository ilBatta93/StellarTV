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
import 'package:stellar_tv/widgets/section_row.dart';
import 'package:stellar_tv/widgets/tv_focusable.dart';

void main() {
  for (final downloadable in [true, false]) {
    testWidgets(
      'Episode horizontal lane and Down actions download=$downloadable',
      (tester) async {
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
                  child: HorizontalRow(
                    horizontalFocusFilter: (node) =>
                        node is EpisodePlaybackFocusNode,
                    height: 300,
                    spacing: 20,
                    itemCount: 4,
                    itemBuilder: (_, i) => EpisodeCard(
                      episode: SeriesEpisode(
                        channel: Channel(
                          id: '$i',
                          name: 'Episode $i',
                          url: downloadable
                              ? 'https://example.invalid/$i.mp4'
                              : '',
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
        for (final node in FocusManager.instance.rootScope.descendants) {
          if (node is EpisodePlaybackFocusNode) node.debugLabel = null;
        }
        FocusManager.instance.primaryFocus?.nextFocus();
        await tester.pump();
        await tester.sendKeyEvent(
          LogicalKeyboardKey.select,
          platform: 'android',
        );
        await tester.pump();
        expect(played, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        await tester.sendKeyEvent(
          LogicalKeyboardKey.select,
          platform: 'android',
        );
        await tester.pump();
        expect(played, 1);
        expect(
          FocusManager.instance.primaryFocus,
          isA<EpisodePlaybackFocusNode>(),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          downloadable ? 'episode-download:1' : 'episode-watched:1',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'episode-watched:1',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'episode-info:1',
        );
        await tester.sendKeyEvent(
          LogicalKeyboardKey.select,
          platform: 'android',
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'episode-info:1',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus,
          isA<EpisodePlaybackFocusNode>(),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        await tester.sendKeyEvent(
          LogicalKeyboardKey.select,
          platform: 'android',
        );
        await tester.pump();
        expect(played, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
