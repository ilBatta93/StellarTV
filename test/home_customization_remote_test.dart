import 'dart:io';
import 'dart:ui' as image_ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/models/home_layout_preferences.dart';
import 'package:stellar_tv/providers/app_provider.dart';
import 'package:stellar_tv/providers/discover_provider.dart';
import 'package:stellar_tv/providers/history_provider.dart';
import 'package:stellar_tv/providers/profile_provider.dart';
import 'package:stellar_tv/providers/reactions_provider.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/providers/sync_provider.dart';
import 'package:stellar_tv/screens/discover_page.dart';
import 'package:stellar_tv/screens/settings_screen.dart';
import 'package:stellar_tv/services/profile_service.dart';
import 'package:stellar_tv/services/sync_service.dart';
import 'package:stellar_tv/theme/app_theme.dart';
import 'package:stellar_tv/widgets/ui_scale.dart';
import 'package:stellar_tv/widgets/home_art.dart';
import 'package:stellar_tv/widgets/poster_card.dart';
import 'package:stellar_tv/widgets/tv_focusable.dart';

import 'home_banner_remote_test.dart' as f;
import 'october_live_multiview_test.dart' as remote;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  remote.mainSetupForRemote();
  setUp(() async {
    for (final family in ['Sora', 'Manrope', 'MaterialIcons']) {
      final loader = FontLoader(family)
        ..addFont(
          rootBundle.load(
            family == 'MaterialIcons'
                ? 'fonts/MaterialIcons-Regular.otf'
                : 'assets/fonts/$family.ttf',
          ),
        );
      await loader.load();
    }
  });
  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    testWidgets('Home shapes density scale and remote fit $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = SupabaseClient(
        'https://example.invalid',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );

      final sync = SyncService(client);
      final app = f.HomeApp(), tmdb = f.FakeTmdb();
      final settings = UiSettings();
      await settings.load();
      final discover = f.HomeDiscover(tmdb);
      final history = f.HomeHistory(sync);
      final profile = f.HomeProfile(ProfileService(client), sync);
      final reactions = ReactionsProvider();
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppProvider>.value(value: app),
            ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
            ChangeNotifierProvider<HistoryProvider>.value(value: history),
            ChangeNotifierProvider<ProfileProvider>.value(value: profile),
            ChangeNotifierProvider<ReactionsProvider>.value(value: reactions),
            ChangeNotifierProvider<UiSettings>.value(value: settings),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme(isTv: true),
            home: RepaintBoundary(
              key: boundaryKey,
              child: UiScale(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.2)),
                  child: const Scaffold(body: DiscoverPage()),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      for (final scale in [90, 100, 115]) {
        await settings.setUiScale(scale);
        for (final shape in HomePosterShape.values) {
          await settings.setHomePosterShape(shape);
          await settings.setHomeRecentShape(shape);
          await settings.setHomeBannerSize(HomeBannerSize.large);
          await settings.setHomePosterDensity(HomeDensity.spacious);
          await settings.setHomeRecentDensity(HomeDensity.spacious);
          await tester.pump(const Duration(milliseconds: 500));
          expect(tester.takeException(), isNull);
          final poster = find
              .byType(RankedPosterCard, skipOffstage: false)
              .first;
          final stop = find
              .descendant(
                of: poster,
                matching: find.byType(TvFocusable, skipOffstage: false),
                skipOffstage: false,
              )
              .first;
          final focus = find
              .descendant(
                of: stop,
                matching: find.byType(Focus, skipOffstage: false),
                skipOffstage: false,
              )
              .first;
          Focus.of(tester.element(focus)).requestFocus();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump(const Duration(milliseconds: 500));
          expect(tester.takeException(), isNull);
        }
      }
      await settings.resetHomeLayout();
      await tester.pump(const Duration(milliseconds: 500));
      final card = find.byType(HomeLandscapeCard, skipOffstage: false).first;
      final before = tester.getSize(card).width;
      await settings.setHomeRecentDensity(HomeDensity.dense);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.getSize(card).width, lessThan(before));
      final boundary = boundaryKey.currentContext?.findRenderObject();
      if (boundary is RenderRepaintBoundary) {
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(
            format: image_ui.ImageByteFormat.png,
          );
          if (data != null) {
            await Directory('/tmp/stv').create(recursive: true);
            await File('/tmp/stv/customization-${size.width.toInt()}.png')
                .writeAsBytes(data.buffer.asUint8List());
          }
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
      discover.dispose();
      history.dispose();
      profile.dispose();
      reactions.dispose();
      settings.dispose();
    });
  }
  testWidgets(
    'Settings shape picker works with remote and persists selection',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final ui = UiSettings();
      await ui.load();
      final app = f.HomeApp();
      final client = SupabaseClient(
        'https://example.invalid',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );

      final sync = SyncProvider(SyncService(client));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<UiSettings>.value(value: ui),
            ChangeNotifierProvider<AppProvider>.value(value: app),
            ChangeNotifierProvider<SyncProvider>.value(value: sync),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme(isTv: true),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      // TV settings open on the first macro area: move focus down to "Aspetto e Home".
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 500));
      final field = find.text('Forma locandine consigliati e Top');
      final pane = find.byType(ListView).last;
      for (var i = 0; i < 6 && !tester.any(field); i++) {
        await tester.drag(pane, const Offset(0, -400));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.pump(const Duration(milliseconds: 500));
      await tester.ensureVisible(field);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(field);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 500));
      expect(ui.homePosterShape, HomePosterShape.square);
      final shapeRow = find
          .ancestor(of: field, matching: find.byType(TvFocusable))
          .first;
      final contentFocus = tester
          .widget<Focus>(
            find.descendant(of: shapeRow, matching: find.byType(Focus)).first,
          )
          .focusNode;
      expect(contentFocus, isNotNull);
      contentFocus?.requestFocus();
      await tester.pump();
      final category = find
          .ancestor(
            of: find.text('Aspetto e Home'),
            matching: find.byType(TvFocusable),
          )
          .first;
      final activeNode = tester.widget<TvFocusable>(category).focusNode;
      expect(activeNode, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 300));
      expect(activeNode?.hasFocus, true);
      final reload = UiSettings();
      await reload.load();
      expect(reload.homePosterShape, HomePosterShape.square);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      ui.dispose();
      app.dispose();
      sync.dispose();
    },
  );
}
