import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/widgets/tv_catalog_navigation.dart';
import 'package:stellar_tv/widgets/tv_catalog_toolbar.dart';
import 'package:stellar_tv/widgets/tv_filter_panel.dart';
import 'package:stellar_tv/widgets/tv_focusable.dart';

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
    'Lazy inline filters navigate rows, restore tools and close on leaving',
    (tester) async {
      final controller = TextEditingController();
      final tile = FocusNode();
      final menu = FocusNode();
      var built = 0;
      var selected = -1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvCatalogMenu(
              onMenu: menu.requestFocus,
              child: Column(
                children: [
                  TvFocusable(
                    focusNode: menu,
                    onPressed: () {},
                    child: const SizedBox(
                      width: 80,
                      height: 40,
                      child: Text('Menu'),
                    ),
                  ),
                  Expanded(
                    child: TvCatalogNavigation(
                      toolbar: TvCatalogToolbar(
                        controller: controller,
                        hint: 'Cerca',
                        onChanged: (_) {},
                        sort: null,
                        onSort: (_) {},
                        filters: (_) {
                          built++;
                          return TvFilterPanel(
                            options: [
                              for (var i = 0; i < 9; i++)
                                TvFilterOption(
                                  'Categoria numero $i molto lunga',
                                  i == selected,
                                  () {
                                    selected = i;
                                  },
                                ),
                            ],
                          );
                        },
                      ),
                      filters: const SizedBox.shrink(),
                      items: Align(
                        alignment: Alignment.topLeft,
                        child: TvCatalogItem(
                          index: 0,
                          columns: 1,
                          child: TvFocusable(
                            focusNode: tile,
                            onPressed: () {},
                            child: const SizedBox(
                              width: 90,
                              height: 100,
                              child: Text('Titolo'),
                            ),
                          ),
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
      await tester.pumpAndSettle();
      expect(built, 0);
      await tester.tap(find.byTooltip('Filtri e categorie'));
      await tester.pumpAndSettle();
      expect(find.byType(TvFilterPanel), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.ancestors.any(
          (n) => n.debugLabel == 'catalog panel',
        ),
        true,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(selected, 0);
      final start = FocusManager.instance.primaryFocus;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, isNot(start));
      expect(tile.hasFocus, false);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TvFilterPanel), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalogFilters');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(tile.hasFocus, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalogSearch');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(menu.hasFocus, true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      tile.dispose();
      menu.dispose();
      controller.dispose();
    },
  );
}
