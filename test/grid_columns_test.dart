import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/screens/catalog_page.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/services/personal_vault.dart';

/// "Colonne della griglia": a fixed number of posters per row in catalogs
/// and Preferiti, kept apart for TVs and phones.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> setTv(bool tv) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('stellartv/device'),
          (call) async => call.method == 'isTv' ? tv : null,
        );
    await DeviceTypeService.initialize();
  }

  SliverConstraints across(double width) => SliverConstraints(
    axisDirection: AxisDirection.down,
    growthDirection: GrowthDirection.forward,
    userScrollDirection: ScrollDirection.idle,
    scrollOffset: 0,
    precedingScrollExtent: 0,
    overlap: 0,
    remainingPaintExtent: 800,
    crossAxisExtent: width,
    crossAxisDirection: AxisDirection.right,
    viewportMainAxisExtent: 800,
    remainingCacheExtent: 800,
    cacheOrigin: 0,
  );

  tearDown(() => setTv(false));

  group('setting', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('starts automatic and offers the phone counts', () async {
      final ui = UiSettings();
      await ui.load();
      expect(ui.gridColumns, 0);
      expect(UiSettings.gridColumnChoices(), [2, 3, 4, 5]);
      expect(UiSettings.gridColumnChoices(tv: true), [4, 5, 6, 7, 8, 9]);
    });

    test('saves a valid count and ignores the others', () async {
      final ui = UiSettings();
      await ui.load();
      final before = ui.signature;
      await ui.setGridColumns(3);
      expect(ui.gridColumns, 3);
      expect(ui.signature, isNot(before));
      await ui.setGridColumns(9);
      expect(ui.gridColumns, 3);
      final reloaded = UiSettings();
      await reloaded.load();
      expect(reloaded.gridColumns, 3);
      await reloaded.resetAppearance();
      expect(reloaded.gridColumns, 0);
    });

    test('a TV-only count read on a phone falls back to automatic', () async {
      SharedPreferences.setMockInitialValues({UiSettings.gridColumnsKey: 8});
      final ui = UiSettings();
      await ui.load();
      expect(ui.gridColumns, 0);
      await setTv(true);
      expect(ui.gridColumns, 8);
    });

    test('travels apart for TVs and phones', () {
      expect(PersonalVault.settingKeys, contains(UiSettings.gridColumnsKey));
      expect(PersonalVault.layoutKeys, contains(UiSettings.gridColumnsKey));
      expect(PersonalVault.isVaultSettingKey('ui_grid_columns@tv'), isTrue);
      expect(PersonalVault.isVaultSettingKey('ui_grid_columns@touch'), isTrue);
    });
  });

  group('grid', () {
    test('automatic keeps the poster-size grid', () {
      final auto = channelGridDelegate(ContentType.movie);
      expect(auto, isNot(isA<FixedColumnsGridDelegate>()));
      expect(gridColumnCount(auto, 360), 3);
    });

    test('fixed columns fill the width whatever the poster size', () {
      for (final extent in [120.0, 170.0]) {
        final fixed = channelGridDelegate(
          ContentType.series,
          maxExtent: extent,
          columns: 4,
          width: 400,
        );
        expect(fixed, isA<FixedColumnsGridDelegate>());
        expect(gridColumnCount(fixed, 400), 4);
        final layout =
            fixed.getLayout(across(400)) as SliverGridRegularTileLayout;
        expect(layout.crossAxisCount, 4);
        // 400 minus three 12px gaps, split in four.
        expect(layout.childCrossAxisExtent, closeTo(91, 0.001));
        expect(
          layout.childMainAxisExtent,
          closeTo(91 / fixed.childAspectRatio, 0.001),
        );
        // The estimate the TV row prefetch reads matches the real cell.
        expect(fixed.maxCrossAxisExtent, closeTo(91, 0.001));
      }
    });

    test('keeps the cell shape of titles and details', () {
      final plain = channelGridDelegate(ContentType.movie);
      final fixed = channelGridDelegate(ContentType.movie, columns: 2);
      expect(fixed.childAspectRatio, plain.childAspectRatio);
      final posterOnly = channelGridDelegate(
        ContentType.movie,
        showTitles: false,
        columns: 2,
      );
      expect(posterOnly.childAspectRatio, closeTo(2 / 3, 0.0001));
    });

    test('live channels stay automatic', () {
      final live = channelGridDelegate(ContentType.live, columns: 4);
      expect(live, isNot(isA<FixedColumnsGridDelegate>()));
    });

    test('a new count relays the grid out', () {
      final three = channelGridDelegate(ContentType.movie, columns: 3);
      final four = channelGridDelegate(ContentType.movie, columns: 4);
      final auto = channelGridDelegate(ContentType.movie);
      expect(four.shouldRelayout(three), isTrue);
      expect(three.shouldRelayout(auto), isTrue);
      expect(
        three.shouldRelayout(
          channelGridDelegate(ContentType.movie, columns: 3),
        ),
        isFalse,
      );
    });

    testWidgets('a grid shows exactly the chosen posters per row', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final delegate = channelGridDelegate(
        ContentType.movie,
        columns: 5,
        width: 600,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GridView.builder(
            gridDelegate: delegate,
            itemCount: 12,
            itemBuilder: (_, i) => SizedBox(key: ValueKey(i)),
          ),
        ),
      );
      final first = tester.getTopLeft(find.byKey(const ValueKey(0)));
      final fifth = tester.getTopLeft(find.byKey(const ValueKey(4)));
      final sixth = tester.getTopLeft(find.byKey(const ValueKey(5)));
      expect(fifth.dy, first.dy);
      expect(sixth.dy, greaterThan(first.dy));
      expect(sixth.dx, first.dx);
    });
  });
}
