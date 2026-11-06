import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/poster_focus.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/services/personal_vault.dart';
import 'package:stellar_tv/widgets/tv_focusable.dart';

/// "Effetto di selezione" on TV: zoom and ring of posters and covers only.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> device({required bool tv}) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('stellartv/device'),
          (call) async => call.method == 'isTv' ? tv : null,
        );
    await DeviceTypeService.initialize();
  }

  tearDown(() => device(tv: false));

  test('starts as today, persists, resets', () async {
    SharedPreferences.setMockInitialValues({});
    final ui = UiSettings();
    await ui.load();
    expect(ui.focusZoom, PosterFocusZoom.normal);
    expect(ui.focusRing, PosterFocusRing.thin);
    expect(ui.focusZoom.scale, 1.06);
    expect(ui.focusRing.width, 2.5);
    final before = ui.signature;
    await ui.setFocusZoom(PosterFocusZoom.wide);
    await ui.setFocusRing(PosterFocusRing.thick);
    expect(ui.signature, isNot(before));
    final again = UiSettings();
    await again.load();
    expect(again.focusZoom, PosterFocusZoom.wide);
    expect(again.focusRing, PosterFocusRing.thick);
    await again.resetAppearance();
    expect(again.focusZoom, PosterFocusZoom.normal);
    expect(again.focusRing, PosterFocusRing.thin);
  });

  test('unknown values fall back to the standard effect', () {
    expect(PosterFocusZoomInfo.parse('???'), PosterFocusZoom.normal);
    expect(PosterFocusRingInfo.parse(3), PosterFocusRing.thin);
  });

  test('a selection always stays visible', () {
    expect(
      posterFocusRingWidth(PosterFocusZoom.none, PosterFocusRing.none),
      PosterFocusRing.thin.width,
    );
    expect(
      posterFocusRingWidth(PosterFocusZoom.light, PosterFocusRing.none),
      0,
    );
    expect(
      posterFocusRingWidth(PosterFocusZoom.none, PosterFocusRing.thick),
      4,
    );
  });

  test('both choices are synced', () {
    expect(PersonalVault.settingKeys, contains(UiSettings.focusZoomKey));
    expect(PersonalVault.settingKeys, contains(UiSettings.focusRingKey));
  });

  Future<({double scale, BorderSide side})> focused(
    WidgetTester tester,
    UiSettings ui, {
    required bool poster,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: ui,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: TvFocusable(
                autofocus: true,
                poster: poster,
                onPressed: () {},
                child: const SizedBox(width: 100, height: 150),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final transform = tester.widget<Transform>(
      find.descendant(
        of: find.byType(TvFocusable),
        matching: find.byType(Transform),
      ),
    );
    final box = tester.widget<Container>(
      find.descendant(
        of: find.byType(TvFocusable),
        matching: find.byType(Container),
      ),
    );
    final shape = (box.foregroundDecoration! as ShapeDecoration).shape;
    return (
      scale: transform.transform.getMaxScaleOnAxis(),
      side: (shape as OutlinedBorder).side,
    );
  }

  Future<UiSettings> settings(
    PosterFocusZoom zoom,
    PosterFocusRing ring,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final ui = UiSettings();
    await ui.load();
    await ui.setFocusZoom(zoom);
    await ui.setFocusRing(ring);
    return ui;
  }

  testWidgets('posters follow the chosen zoom and ring', (tester) async {
    await device(tv: true);
    final ui = await settings(PosterFocusZoom.wide, PosterFocusRing.thick);
    final effect = await focused(tester, ui, poster: true);
    expect(effect.scale, closeTo(1.12, 1e-6));
    expect(effect.side.width, 4);
  });

  testWidgets('no ring draws nothing, not a hairline', (tester) async {
    await device(tv: true);
    final ui = await settings(PosterFocusZoom.light, PosterFocusRing.none);
    final effect = await focused(tester, ui, poster: true);
    expect(effect.scale, closeTo(1.03, 1e-6));
    expect(effect.side, BorderSide.none);
  });

  testWidgets('buttons and menus keep the standard effect', (tester) async {
    await device(tv: true);
    final ui = await settings(PosterFocusZoom.none, PosterFocusRing.none);
    final effect = await focused(tester, ui, poster: false);
    expect(effect.scale, closeTo(1.06, 1e-6));
    expect(effect.side.width, 2.5);
  });
}
