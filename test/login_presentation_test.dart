import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/widgets/brand_intro.dart';
import 'package:stellar_tv/screens/account_screen.dart';
import 'package:stellar_tv/screens/login_screen.dart';
import 'package:stellar_tv/theme/app_theme.dart';

Future<void> device(bool tv) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('stellartv/device'),
        (call) async => call.method == 'isTv' ? tv : false,
      );
  await DeviceTypeService.initialize();
  debugDefaultTargetPlatformOverride = null;
}

/// A few frames, without waiting for idle. A focused field keeps the caret
/// ticking, so pumpAndSettle would never return.
Future<void> frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  for (final tv in [true, false]) {
    for (final account in [true, false]) {
      testWidgets(
        '${tv ? "TV" : "Phone"} ${account ? "account" : "Xtream"}: keyboard only on activation and reopens',
        (tester) async {
          await device(tv);
          tester.view.physicalSize = tv
              ? const Size(960, 540)
              : const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.darkTheme(isTv: tv),
              home: account ? const AccountScreen() : const LoginScreen(),
            ),
          );
          await frames(tester);
          expect(tester.testTextInput.isVisible, isFalse);
          expect(tester.testTextInput.hasAnyClients, isFalse);
          if (tv) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await frames(tester);
            expect(tester.testTextInput.isVisible, isFalse);
            await tester.sendKeyEvent(LogicalKeyboardKey.select);
          } else {
            await tester.tap(find.byType(TextField).first);
          }
          await frames(tester);
          expect(tester.testTextInput.isVisible, isTrue);
          tester.testTextInput.enterText('test-value');
          await tester.pump();
          expect(
            find
                .byType(TextField)
                .evaluate()
                .any(
                  (e) =>
                      (e.widget as TextField).controller?.text == 'test-value',
                ),
            isTrue,
          );
          if (tv) {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await frames(tester);
            expect(tester.testTextInput.isVisible, isFalse);
            await tester.sendKeyEvent(LogicalKeyboardKey.select);
          } else {
            tester.testTextInput.hide();
            await tester.tap(find.byType(TextField).first);
          }
          await frames(tester);
          expect(tester.testTextInput.isVisible, isTrue);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await frames(tester);
        },
      );
    }
  }
  test('Logo reveals symbol then STELLAR then TV without changing routing', () {
    expect(BrandIntroFrame.at(0).symbol, 0);
    expect(BrandIntroFrame.at(.20).symbol, 1);
    expect(BrandIntroFrame.at(.20).shift, 0);
    expect(BrandIntroFrame.at(.60).shift, 1);
    expect(BrandIntroFrame.at(.60).stellar, 0);
    expect(BrandIntroFrame.at(.80).stellar, 1);
    expect(BrandIntroFrame.at(.80).tv, 0);
    expect(BrandIntroFrame.at(1).tv, 1);
  });
}
