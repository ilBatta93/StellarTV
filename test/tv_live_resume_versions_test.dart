import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/providers/app_provider.dart';
import 'package:stellar_tv/providers/epg_provider.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/screens/live_page.dart';
import 'package:stellar_tv/services/live_variants.dart';
import 'package:stellar_tv/services/recent_live_channels.dart';
import 'package:stellar_tv/theme/app_theme.dart';
import 'package:stellar_tv/widgets/tv_focusable.dart';

import 'october_live_multiview_test.dart' as fixtures;

Channel live(String id, String name) => Channel(
  id: id,
  name: name,
  url: 'https://example.invalid/$id',
  logo: '',
  group: 'TV',
  type: ContentType.live,
);

class VersionsApp extends fixtures.TestApp {
  @override
  List<Channel> get channels => _channels;
  final _channels = [
    live('a', 'Rai 1'),
    live('b', 'Rai 1 FHD'),
    live('c', 'Rai 2'),
    live('d', 'Rai 1 4K'),
  ];
  @override
  Future<List<Map<String, String>>> liveIdentities() async => [
    for (final c in _channels) {'id': c.id, 'name': c.name},
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  fixtures.mainSetupForRemote();
  setUp(() => LiveVariants.instance.reset());

  Future<void> pumpGuide(WidgetTester tester, VersionsApp app) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: app),
          ChangeNotifierProvider<EpgProvider>.value(
            value: fixtures.TestEpg(app),
          ),
          ChangeNotifierProvider<UiSettings>.value(value: UiSettings()),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(isTv: true),
          home: const Scaffold(body: LivePage(active: false)),
        ),
      ),
    );
    // Groups are built off the UI isolate.
    await tester.runAsync(
      () => LiveVariants.instance.bind(1, app.liveIdentities),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('le versioni dello stesso canale occupano una riga', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    RecentLiveChannels.instance.reset();
    await pumpGuide(tester, VersionsApp());
    expect(tester.takeException(), isNull);
    expect(find.text('Rai 1 FHD'), findsOneWidget);
    expect(find.text('Rai 1'), findsNothing);
    expect(find.text('Rai 1 4K'), findsNothing);
    expect(find.text('Rai 2'), findsOneWidget);
    expect(find.text('Full HD ×3'), findsOneWidget);
    expect(find.text('Riprendi'), findsNothing);
  });

  testWidgets('Riprendi porta all\'ultimo canale ed è il primo passo', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'recent_live_channels_v1': ['c'],
    });
    RecentLiveChannels.instance.reset();
    await pumpGuide(tester, VersionsApp());
    expect(tester.takeException(), isNull);
    expect(find.text('Riprendi'), findsOneWidget);
    final entry = find.byWidgetPredicate(
      (w) => w is Focus && w.focusNode is TvEntryFocusNode,
    );
    expect(entry, findsOneWidget);
    tester.widget<Focus>(entry).focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final primary = FocusManager.instance.primaryFocus;
    expect(primary, isNot(isA<TvEntryFocusNode>()));
    expect(primary?.debugLabel, startsWith('live-channel-'));
  });
}
