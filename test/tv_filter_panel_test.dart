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
  testWidgets('rapid filter arrows stay in the row and panel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 650,
            child: TvFilterPanel(
              options: [
                for (var i = 0; i < 9; i++)
                  TvFilterOption('Option $i', false, () {}),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final nodes = tester
        .widgetList<TvFocusable>(find.byType(TvFocusable))
        .map((w) => w.focusNode)
        .whereType<FocusNode>()
        .toList();
    nodes[4].requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(nodes[0].hasFocus, true);
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    await tester.pumpAndSettle();
    expect(nodes[2].hasFocus, true);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(nodes[4].hasFocus, true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
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
  for (final section in ['Film', 'Serie TV']) {
    for (final platform in [false, true]) {
      testWidgets(
        '$section ${platform ? 'platform' : 'genre'} Back restores opener without menu jump',
        (tester) async {
          final controller = TextEditingController();
          final menu = FocusNode();
          final tile = FocusNode();
          var menuBacks = 0;
          Widget panel(BuildContext _) => TvFilterPanel(
            options: [
              TvFilterOption('Tutte', true, () {}),
              TvFilterOption('Filtro', false, () {}),
            ],
          );
          await tester.pumpWidget(
            MaterialApp(
              home: PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop &&
                      !TvCatalogToolbar.handleBack(
                        FocusManager.instance.primaryFocus,
                      )) {
                    menuBacks++;
                    menu.requestFocus();
                  }
                },
                child: Scaffold(
                  body: Column(
                    children: [
                      TvFocusable(
                        focusNode: menu,
                        onPressed: () {},
                        child: const SizedBox(height: 40, child: Text('Menu')),
                      ),
                      TvCatalogToolbar(
                        controller: controller,
                        hint: section,
                        onChanged: (_) {},
                        onSort: (_) {},
                        sort: null,
                        genresOnly: true,
                        filters: panel,
                        platforms: platform ? panel : null,
                      ),
                      TvFocusable(
                        focusNode: tile,
                        onPressed: () {},
                        child: const SizedBox(
                          height: 40,
                          child: Text('Titolo'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final tooltip = platform
              ? 'Piattaforme streaming'
              : 'Filtri per genere';
          final opener = tester
              .widget<TvFocusable>(
                find.ancestor(
                  of: find.byTooltip(tooltip),
                  matching: find.byType(TvFocusable),
                ),
              )
              .focusNode;
          await tester.tap(find.byTooltip(tooltip));
          await tester.pumpAndSettle();
          // Resolve system Back even with a focus reference outside the toolbar.
          expect(TvCatalogToolbar.handleBack(tile), isTrue);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.byType(TvFilterPanel), findsNothing);
          expect(opener?.hasFocus, isTrue);
          expect(menu.hasFocus, isFalse);
          expect(menuBacks, 0);
          // Hardware Back and a duplicate system dispatch must be consumed once.
          await tester.tap(find.byTooltip(tooltip));
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(
            LogicalKeyboardKey.goBack,
            physicalKey: PhysicalKeyboardKey.escape,
          );
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(opener?.hasFocus, isTrue);
          expect(menuBacks, 0);
          // A new, subsequent Back retains the existing menu navigation.
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(menu.hasFocus, isTrue);
          expect(menuBacks, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          menu.dispose();
          tile.dispose();
        },
      );
    }
  }
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
