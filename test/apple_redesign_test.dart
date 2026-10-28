import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/theme/app_theme.dart';
import 'package:stellar_tv/widgets/apple_page_scaffold.dart';
import 'package:stellar_tv/widgets/settings_tiles.dart';
import 'package:stellar_tv/widgets/tv_focusable.dart';
import 'package:stellar_tv/widgets/tv_text_field.dart';
import 'package:stellar_tv/widgets/player/tv_player_controls.dart';

Future<void> device(bool tv) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('stellartv/device'),
        (_) async => tv,
      );
  await DeviceTypeService.initialize();
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    testWidgets('TV player actions fit ${size.width}', (tester) async {
      await device(true);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      TvPlayerAction action(String name, {bool primary = false}) =>
          TvPlayerAction(
            id: name,
            label: name,
            icon: Icons.play_arrow_rounded,
            onPressed: () {},
            primary: primary,
          );
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(isTv: true),
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: TvPlayerControls(
                rows: [
                  TvPlayerRow(
                    TvPlayerRowKind.top,
                    [
                      'Indietro',
                      'Stagioni ed episodi',
                      'Scheda titolo',
                      'MPV',
                      'Picture-in-Picture',
                      'Opzioni',
                    ].map((n) => action(n)).toList(),
                  ),
                  TvPlayerRow(TvPlayerRowKind.center, [
                    action('Indietro 10 s'),
                    action('Riproduci', primary: true),
                    action('Avanti 10 s'),
                  ]),
                  const TvPlayerRow(TvPlayerRowKind.progress, []),
                  TvPlayerRow(
                    TvPlayerRowKind.bottom,
                    [
                      'Volume',
                      'Ferma registrazione',
                      'Blocca',
                      'Audio',
                      'ITA online',
                      '1.0×',
                      'Adatta schermo',
                    ].map((n) => action(n)).toList(),
                  ),
                ],
                selectedRow: TvPlayerRowKind.bottom,
                selectedColumn: 4,
                title: 'Un titolo lungo di una serie televisiva • Stagione 1',
                subtitle: 'Episodio 3',
                isLive: false,
                locked: false,
                position: const Duration(minutes: 12),
                duration: const Duration(minutes: 45),
                buffered: const Duration(minutes: 14),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary = key.currentContext?.findRenderObject();
      if (boundary is RenderRepaintBoundary) {
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          if (bytes != null) {
            await File('/tmp/stv/apple-player-${size.width.toInt()}.png')
                .writeAsBytes(bytes.buffer.asUint8List());
          }
          image.dispose();
        });
      }
    });
  }
  testWidgets(
    'Grouped settings remote switches, values and slider remain reachable',
    (tester) async {
      await device(true);
      var value = false;
      var opened = 0;
      var slider = 5.0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(isTv: true),
          home: StatefulBuilder(
            builder: (context, setState) => ApplePageScaffold(
              title: 'Impostazioni',
              body: ListView(
                children: [
                  SettingsSection(
                    title: 'Riproduzione',
                    children: [
                      SettingsSwitchTile(
                        icon: Icons.image,
                        title: 'Mostra anteprime',
                        value: value,
                        onChanged: (v) => setState(() => value = v),
                      ),
                      SettingsValueTile(
                        icon: Icons.play_arrow,
                        title: 'Player video',
                        onTap: () => opened++,
                      ),
                      SettingsSliderTile(
                        icon: Icons.volume_up,
                        title: 'Volume',
                        value: slider,
                        min: 0,
                        max: 10,
                        divisions: 10,
                        format: (v) => '$v',
                        onChanged: (v) => setState(() => slider = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final stops = tester
          .widgetList<TvFocusable>(find.byType(TvFocusable))
          .toList();
      final element = find.byWidget(stops.first).evaluate().first;
      Focus.of(element, scopeOk: true).nextFocus();
      await tester.pumpAndSettle();
      // Activate the actual first row via its focus descendant.
      final focus = find
          .descendant(
            of: find.byWidget(stops.first),
            matching: find.byType(Focus),
          )
          .first;
      final node = tester.widget<Focus>(focus).focusNode;
      if (node != null) {
        node.requestFocus();
      } else {
        Focus.of(
          tester.element(
            find.descendant(
              of: find.byWidget(stops.first),
              matching: find.byType(SwitchListTile),
            ),
          ),
        ).requestFocus();
      }
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select, platform: 'android');
      await tester.pumpAndSettle();
      expect(value, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select, platform: 'android');
      expect(opened, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(slider, 6);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Focus lift respects disabled animations', (tester) async {
    await device(true);
    final settings = UiSettings();
    await tester.runAsync(() => settings.setAnimations(false));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: TvFocusable(
              autofocus: true,
              onPressed: () {},
              child: const SizedBox(width: 100, height: 60),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scale = tester.widget<Transform>(
      find.descendant(
        of: find.byType(TvFocusable),
        matching: find.byType(Transform),
      ),
    );
    expect(scale.transform.getMaxScaleOnAxis(), 1);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
  testWidgets('Profile name input retains its 20 character limit', (
    tester,
  ) async {
    await device(false);
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvTextField(controller: controller, maxLength: 20),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '123456789012345678901234');
    expect(controller.text.length, 20);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
