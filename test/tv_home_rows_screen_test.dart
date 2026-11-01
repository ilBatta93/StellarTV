import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stellar_tv/models/home_layout_preferences.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/screens/home_rows_screen.dart';
import 'package:stellar_tv/theme/app_theme.dart';

import 'october_live_multiview_test.dart' as remote;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  remote.mainSetupForRemote();

  Future<UiSettings> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ui = UiSettings();
    await ui.load();
    await tester.pumpWidget(
      ChangeNotifierProvider<UiSettings>.value(
        value: ui,
        child: MaterialApp(
          theme: AppTheme.darkTheme(isTv: true),
          home: const HomeRowsScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return ui;
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('OK hides and shows the focused Home row', (tester) async {
    final ui = await open(tester);
    expect(find.text('Serie viste di recente'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.select);
    expect(ui.homeHiddenRows, {HomeRows.recentSeries});
    expect(find.text('Nascosta'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.select);
    expect(ui.homeHiddenRows, isEmpty);
  });

  testWidgets('Sposta moves a row with Su/Giù and Back drops it', (
    tester,
  ) async {
    final ui = await open(tester);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.select);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(homeRowsOrder(ui).take(3), [
      HomeRows.recentMovies,
      HomeRows.forYouMovies,
      HomeRows.recentSeries,
    ]);
    // Left/Right stay on the row while moving; Back ends the move first.
    await press(tester, LogicalKeyboardKey.arrowLeft);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(HomeRowsScreen), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(homeRowsOrder(ui).indexOf(HomeRows.recentSeries), 2);
  });
}
