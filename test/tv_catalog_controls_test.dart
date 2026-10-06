import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/widgets/tv_catalog_toolbar.dart';

Channel item(String id, String name, int date) => Channel(
  id: id,
  name: name,
  url: '',
  logo: '',
  group: 'Test',
  type: ContentType.movie,
  addedAt: date,
);

void main() {
  test('Sort by name/date/rating without mutating source; unknown last', () {
    final source = [
      item('b', 'Beta', 200),
      item('a', 'Alpha', 100),
      item('c', 'Gamma', 0),
    ];
    List<String> ids(CatalogSort order) => sortCatalog(
      source,
      order,
      (c) => c,
      ratingOf: (c) => c.id == 'a'
          ? 8
          : c.id == 'b'
          ? 6
          : null,
    ).map((c) => c.id).toList();
    expect(ids(CatalogSort.provider), ['b', 'a', 'c']);
    expect(ids(CatalogSort.nameAsc), ['a', 'b', 'c']);
    expect(ids(CatalogSort.nameDesc), ['c', 'b', 'a']);
    expect(ids(CatalogSort.dateAsc), ['a', 'b', 'c']);
    expect(ids(CatalogSort.dateDesc), ['b', 'a', 'c']);
    expect(ids(CatalogSort.rating), ['a', 'b', 'c']);
    expect(source.map((c) => c.id), ['b', 'a', 'c']);
  });

  testWidgets('TV search starts hidden, opens on OK, and sort returns focus', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('stellartv/device'),
          (_) async => true,
        );
    await DeviceTypeService.initialize();
    debugDefaultTargetPlatformOverride = null;
    final controller = TextEditingController();
    CatalogSort? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvCatalogToolbar(
            controller: controller,
            hint: 'Cerca',
            onChanged: (_) {},
            sort: null,
            allowRating: false,
            onSort: (value) => selected = value,
          ),
        ),
      ),
    );
    expect(find.byType(TextField), findsNothing);
    final search = find.byTooltip('Cerca');
    await tester.tap(search);
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chiudi ricerca'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select, platform: 'android');
    await tester.pumpAndSettle();
    expect(find.text('Ordina'), findsOneWidget);
    expect(find.text('Voto'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.select, platform: 'android');
    await tester.pumpAndSettle();
    expect(selected, CatalogSort.nameAsc);
    expect(find.text('Ordina'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.select, platform: 'android');
    await tester.pumpAndSettle();
    expect(find.text('Ordina'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('TV Back closes keyboard then search and restores lens focus', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('stellartv/device'),
          (_) async => true,
        );
    await DeviceTypeService.initialize();
    debugDefaultTargetPlatformOverride = null;
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvCatalogToolbar(
            controller: controller,
            hint: 'Cerca',
            onChanged: (_) {},
            onSort: (_) {},
            sort: null,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Cerca'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.byType(TextField), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalogSearch');
    // System Back goes through Home's PopScope rather than a key event.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(
      TvCatalogToolbar.handleBack(FocusManager.instance.primaryFocus),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(
      TvCatalogToolbar.handleBack(FocusManager.instance.primaryFocus),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalogSearch');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'TV genre panel Back restores its icon with key and system Back',
    (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvCatalogToolbar(
              controller: controller,
              hint: 'Cerca',
              onChanged: (_) {},
              onSort: (_) {},
              sort: null,
              genresOnly: true,
              filters: (_) =>
                  TextButton(onPressed: () {}, child: const Text('Azione')),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.style_outlined), findsOneWidget);
      await tester.tap(find.byTooltip('Filtri per genere'));
      await tester.pumpAndSettle();
      expect(find.text('Azione'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Azione'), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalogFilters');
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(
        TvCatalogToolbar.handleBack(FocusManager.instance.primaryFocus),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(find.text('Azione'), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalogFilters');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
