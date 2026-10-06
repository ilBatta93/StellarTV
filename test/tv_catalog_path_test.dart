import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/widgets/tv_focusable.dart';
import 'package:stellar_tv/widgets/tv_catalog_navigation.dart';
import 'package:stellar_tv/widgets/tv_catalog_toolbar.dart';

void main() {
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
  testWidgets(
    'Menu tools first filter grid and inverse; search clear and collapse',
    (tester) async {
      final menu = FocusNode(),
          first = FocusNode(),
          second = FocusNode(),
          tile = FocusNode();
      final controller = TextEditingController();
      Widget control(FocusNode node, String text) => TvFocusable(
        focusNode: node,
        onPressed: () {},
        child: SizedBox(width: 90, height: 44, child: Text(text)),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvCatalogMenu(
              onMenu: menu.requestFocus,
              child: Column(
                children: [
                  control(menu, 'Menu'),
                  Expanded(
                    child: TvCatalogNavigation(
                      toolbar: TvCatalogToolbar(
                        controller: controller,
                        hint: 'Cerca',
                        onChanged: (_) {},
                        onSort: (_) {},
                        sort: null,
                      ),
                      filters: Row(
                        children: [
                          control(first, 'Primo'),
                          control(second, 'Secondo'),
                        ],
                      ),
                      items: Align(
                        alignment: Alignment.topLeft,
                        child: TvCatalogItem(
                          index: 0,
                          columns: 1,
                          child: control(tile, 'Titolo'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final searchNode = tester
          .widget<TvFocusable>(
            find.ancestor(
              of: find.byTooltip('Cerca'),
              matching: find.byType(TvFocusable),
            ),
          )
          .focusNode;
      searchNode?.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(first.hasFocus, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(second.hasFocus, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(tile.hasFocus, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(first.hasFocus, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(searchNode?.hasFocus, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(menu.hasFocus, true);
      await tester.tap(find.byTooltip('Cerca'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Film');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cancella ricerca'));
      await tester.pumpAndSettle();
      expect(controller.text, '');
      searchNode?.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(first.hasFocus, true);
      await tester.pumpWidget(const SizedBox());
      menu.dispose();
      first.dispose();
      second.dispose();
      tile.dispose();
      controller.dispose();
    },
  );
}
