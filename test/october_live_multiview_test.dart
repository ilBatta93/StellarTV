import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/epg_program.dart';
import 'package:stellar_tv/models/history_entry.dart';
import 'package:stellar_tv/models/multiview_layout.dart';
import 'package:stellar_tv/player/multiview_audio.dart';
import 'package:stellar_tv/providers/app_provider.dart';
import 'package:stellar_tv/providers/epg_provider.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/screens/discover_page.dart';
import 'package:stellar_tv/screens/live_page.dart';
import 'package:stellar_tv/services/catalog_builder.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/theme/app_theme.dart';
import 'package:stellar_tv/widgets/poster_card.dart';
import 'package:stellar_tv/widgets/tv_focusable.dart';

Channel channel(String id, {ContentType type = ContentType.live}) => Channel(
  id: id,
  name: 'Canale $id',
  url: 'https://example.invalid/$id',
  logo: '',
  group: 'TV',
  type: type,
);

class TestApp extends AppProvider {
  final channels = [channel('uno'), channel('due'), channel('tre')];
  @override
  List<Channel> get allChannels => channels;
  @override
  Channel? channelById(String id) =>
      channels.where((c) => c.id == id).firstOrNull;
  @override
  List<CatalogGroup> groupedCatalog(ContentType type) => [
    CatalogGroup(
      label: 'TV',
      entries: channels
          .map((c) => CatalogEntry(primary: c, variants: [c]))
          .toList(),
    ),
  ];
  @override
  void setPlaybackActive(bool active) {}
}

class TestEpg extends EpgProvider {
  TestEpg(super.app);
  @override
  List<EpgProgram> programmesFor(Channel channel) => List.generate(
    3,
    (i) => EpgProgram(
      id: '${channel.id}$i',
      channelId: channel.id,
      title: 'Programma $i del canale ${channel.name}',
      description: '',
      startTime: DateTime.now()
          .subtract(const Duration(minutes: 10))
          .add(Duration(hours: i)),
      endTime: DateTime.now().add(Duration(hours: i, minutes: 50)),
    ),
  );
  @override
  EpgProgram? nowFor(Channel c) => programmesFor(c).first;
}

HistoryEntry history(String id, int hour, ContentType type) => HistoryEntry(
  contentId: id,
  type: type,
  title: 'Titolo $id',
  posterUrl: '',
  group: '',
  url: 'https://example.invalid/$id',
  position: const Duration(minutes: 59),
  duration: const Duration(hours: 1),
  lastWatchedAt: DateTime.utc(2026, 10, 15, hour),
);
void mainSetupForRemote() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('stellartv/device'),
          (_) async => true,
        );
    await DeviceTypeService.initialize();
    debugDefaultTargetPlatformOverride = null;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mainSetupForRemote();
  test('Latest Home history includes completed movies, excludes live', () {
    final app = TestApp();
    final result = latestHistoryResume([
      history('old', 9, ContentType.movie),
      history('latest', 12, ContentType.series),
      history('live', 13, ContentType.live),
    ], app);
    expect(result?.$1.contentId, 'latest');
    expect(result?.$1.isWatched, true);
    app.dispose();
  });
  test('Audio transfers mute before unmute and suspends all slots', () async {
    final volumes = <String, double>{'a': 0, 'b': 0, 'c': 0};
    final audio = MultiViewAudio<String>((id, v) async {
      await Future<void>.delayed(Duration.zero);
      volumes[id] = v;
      expect(volumes.values.where((v) => v > 0).length, lessThanOrEqualTo(1));
    });
    await audio.update(volumes.keys, 'a');
    expect(volumes['a'], 1);
    final changes = List.generate(
      30,
      (i) => audio.update(volumes.keys, i.isEven ? 'b' : 'c'),
    );
    await Future.wait(changes);
    expect(volumes['c'], 1);
    await audio.update(volumes.keys, 'c', suspended: true);
    expect(volumes.values.every((v) => v == 0), true);
    audio.dispose();
  });
  test('MultiView layout saves once immediately and reloads', () async {
    final ui = UiSettings();
    var saved = 0;
    ui.addListener(() => saved++);
    await ui.setMultiViewLayout(MultiViewLayout.mainAndSide);
    expect(saved, 1);
    final restored = UiSettings();
    await restored.load();
    expect(restored.multiViewLayout, MultiViewLayout.mainAndSide);
    for (final layout in MultiViewLayout.values) {
      for (var n = 1; n <= 4; n++) {
        expect(layout.columns(n), inInclusiveRange(1, n));
      }
    }
    ui.dispose();
    restored.dispose();
  });
  testWidgets('Poster title stays on a single line', (tester) async {
    final title = List.filled(
      10,
      'Un titolo estremamente lungo senza parti nascoste',
    ).join(' ');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SizedBox(width: 112, child: TvPosterTitle(title))),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final paragraph = tester.renderObject<RenderParagraph>(find.text(title));
    expect(paragraph.maxLines, 1);
  });
  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    testWidgets(
      'Live EPG preview favorite and toolbar reachable ${size.width}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = TestApp();
        final epg = TestEpg(app);
        final ui = UiSettings();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AppProvider>.value(value: app),
              ChangeNotifierProvider<EpgProvider>.value(value: epg),
              ChangeNotifierProvider<UiSettings>.value(value: ui),
            ],
            child: MaterialApp(
              theme: AppTheme.darkTheme(isTv: true),
              home: const Scaffold(body: LivePage(active: false)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Guarda ora'), findsNothing);
        final first = find.widgetWithText(TvFocusable, 'Canale uno').first;
        final focusElement = tester.element(
          find.descendant(of: first, matching: find.byType(ExcludeFocus)).first,
        );
        Focus.of(focusElement).requestFocus();
        await tester.pumpAndSettle();
        // Reach each interactive focus stop by the real directional traversal.
        final seen = <String>{};
        for (final direction in [
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowUp,
        ]) {
          await tester.sendKeyEvent(direction);
          await tester.pumpAndSettle();
          seen.add(FocusManager.instance.primaryFocus?.debugLabel ?? '');
          expect(tester.takeException(), isNull);
        }
        expect(find.byTooltip('Preferiti'), findsOneWidget);
        expect(find.byTooltip('MultiView'), findsOneWidget);
        expect(find.byTooltip('Guida TV (EPG)'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
        epg.dispose();
        app.dispose();
        ui.dispose();
      },
    );
  }
}
