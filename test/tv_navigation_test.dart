import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/theme/app_theme.dart';
import 'package:stellar_tv/widgets/tv_category_panel.dart';
import 'package:stellar_tv/widgets/tv_focusable.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('stellartv/device'),
          (_) async => true,
        );
    await DeviceTypeService.initialize();
    debugDefaultTargetPlatformOverride = null;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Remote activates focused controls and navigates right', (
    tester,
  ) async {
    final first = FocusNode();
    final second = FocusNode();
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(isTv: true),
        home: Scaffold(
          body: Row(
            children: [
              TvFocusable(
                focusNode: first,
                autofocus: true,
                onPressed: () => selected = 1,
                child: const SizedBox(
                  width: 80,
                  height: 50,
                  child: Text('Play'),
                ),
              ),
              TvFocusable(
                focusNode: second,
                onPressed: () => selected = 2,
                child: const SizedBox(
                  width: 80,
                  height: 50,
                  child: Text('Audio'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select, platform: 'android');
    expect(selected, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(second.hasFocus, true);
    await tester.sendKeyEvent(LogicalKeyboardKey.select, platform: 'android');
    expect(selected, 2);
    await tester.pumpWidget(const SizedBox());
    first.dispose();
    second.dispose();
  });

  testWidgets('Left edge opens categories and right restores exact tile', (
    tester,
  ) async {
    final scaffold = GlobalKey<ScaffoldState>();
    final tile = FocusNode();
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          key: scaffold,
          onDrawerChanged: (open) {
            if (!open) tile.requestFocus();
          },
          drawer: TvCategoryPanel(
            categories: const {'Film': 12, 'Serie': 8},
            selected: 'Film',
            onSelected: (_) {},
            onClose: () => scaffold.currentState?.closeDrawer(),
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                TvCategoryEdge(
                  scaffoldKey: scaffold,
                  onOpen: () {
                    opens++;
                    scaffold.currentState?.openDrawer();
                  },
                  child: TvFocusable(
                    focusNode: tile,
                    autofocus: true,
                    onPressed: () {},
                    child: const SizedBox(
                      width: 120,
                      height: 180,
                      child: Text('Titolo'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(opens, 1);
    expect(scaffold.currentState?.isDrawerOpen, true);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(scaffold.currentState?.isDrawerOpen, false);
    expect(tile.hasFocus, true);
    await tester.pumpWidget(const SizedBox());
    tile.dispose();
  });

  testWidgets('Touch wrapper introduces no focus target', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('stellartv/device'),
          (_) async => false,
        );
    await DeviceTypeService.initialize();
    debugDefaultTargetPlatformOverride = null;
    final node = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: TvFocusable(
          focusNode: node,
          onPressed: () {},
          child: const Text('Mobile'),
        ),
      ),
    );
    expect(node.context, isNull);
    await tester.pumpWidget(const SizedBox());
    node.dispose();
  });
}
