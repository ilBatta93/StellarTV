import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/providers/app_provider.dart';
import 'package:stellar_tv/providers/discover_provider.dart';
import 'package:stellar_tv/providers/epg_provider.dart';
import 'package:stellar_tv/providers/history_provider.dart';
import 'package:stellar_tv/providers/profile_provider.dart';
import 'package:stellar_tv/providers/reactions_provider.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/screens/home_screen.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/services/catalog_builder.dart';
import 'package:stellar_tv/services/profile_service.dart';
import 'package:stellar_tv/services/sync_service.dart';
import 'package:stellar_tv/theme/app_theme.dart';
import 'home_banner_remote_test.dart' as home;
import 'october_live_multiview_test.dart' as fixtures;

class MenuApp extends home.HomeApp {
  @override
  List<CatalogEntry> recentEntries(ContentType type, {int limit = 100}) => [
    for (final c in channels.take(limit))
      CatalogEntry(primary: c.copyWith(type: type), variants: [c.copyWith(type: type)]),
  ];
}

class LiveSettings extends UiSettings {
  @override
  bool get loaded => true;
  LiveSettings({this.initial = AppSection.live, this.reordered = false});
  final AppSection initial;
  final bool reordered;
  @override
  List<AppSection> get sectionOrder => reordered
      ? [AppSection.series, AppSection.home, AppSection.live, AppSection.movies]
      : List.of(AppSection.values);
  @override
  AppSection get startSection => initial;
  @override
  bool get animations => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  fixtures.mainSetupForRemote();
  setUp(() async {
    for (final family in ['Sora', 'Manrope']) {
      final loader = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/$family.ttf'));
      await loader.load();
    }
  });
  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    for (final initial in [AppSection.live, AppSection.movies, AppSection.series]) {
    for (final reordered in [false, true]) {
    testWidgets('Real HomeScreen Live guide tools main tabs round trip ${size.width} $initial reordered=$reordered', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = SupabaseClient('https://example.invalid', 'test');
      final sync = SyncService(client);
      final app = MenuApp(), discover = home.HomeDiscover(home.FakeTmdb());
      final history = home.HomeHistory(sync);
      final profile = home.HomeProfile(ProfileService(client), sync);
      final epg = fixtures.TestEpg(app);
      final reactions = ReactionsProvider(), settings = LiveSettings(initial: initial, reordered: reordered);
      await tester.pumpWidget(MultiProvider(providers: [
        ChangeNotifierProvider<AppProvider>.value(value: app),
        ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
        ChangeNotifierProvider<HistoryProvider>.value(value: history),
        ChangeNotifierProvider<ProfileProvider>.value(value: profile),
        ChangeNotifierProvider<EpgProvider>.value(value: epg),
        ChangeNotifierProvider<ReactionsProvider>.value(value: reactions),
        ChangeNotifierProvider<UiSettings>.value(value: settings),
      ], child: MaterialApp(theme: AppTheme.darkTheme(isTv: true), home: const HomeScreen())));
      await tester.pump();
      await tester.pump();
      final activeIndex = settings.sectionOrder.indexOf(initial);
      final search = FocusManager.instance.rootScope.descendants.firstWhere(
        (node) => node.debugLabel == 'catalogSearch' && node.canRequestFocus,
      );
      search.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvTab$activeIndex');
      final stops = ['tvNavSearch', 'tvTab0', 'tvTab1', 'tvTab2',
        'tvTab3', 'tvTab4', 'tvNavProfile', 'tvNavSettings'];
      for (var i = activeIndex; i >= 0; i--) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus?.debugLabel, stops[i]);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, stops.first);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, stops[1]);
      for (var i = 2; i < stops.length; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus?.debugLabel, stops[i]);
      }
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, stops.last);
      for (var i = stops.length - 2; i >= activeIndex + 1; i--) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus?.debugLabel, stops[i]);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalogSearch');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.ancestors.any(
        (node) => node.debugLabel == 'catalog items'), true);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvTab$activeIndex');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      epg.dispose(); app.dispose(); discover.dispose(); history.dispose();
      profile.dispose(); reactions.dispose(); settings.dispose();
      client.auth.stopAutoRefresh();
    });
    }
    }
  }
}