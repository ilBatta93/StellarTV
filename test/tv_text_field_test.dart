import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/theme/app_theme.dart';
import 'package:stellar_tv/widgets/tv_text_field.dart';

Future<void> _setTv(bool tv) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('stellartv/device'),
        (call) async => call.method == 'isTv' ? tv : true,
      );
  await DeviceTypeService.initialize();
  debugDefaultTargetPlatformOverride = null;
}

Widget _app(
  TextEditingController a,
  TextEditingController b,
  FocusNode bn, {
  bool openOnFocus = false,
}) {
  return MaterialApp(
    theme: AppTheme.darkTheme(isTv: true),
    home: Scaffold(
      body: AutofillGroup(
        child: Column(
          children: [
            TextButton(
              autofocus: true,
              onPressed: () {},
              child: const Text('Top'),
            ),
            TvTextField(
              openOnFocus: openOnFocus,
              controller: a,
              nextFocus: bn,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TvTextField(
              controller: b,
              focusNode: bn,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Password'),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('TV: D-Pad highlights fields, OK opens the keyboard', (
    tester,
  ) async {
    await _setTv(true);
    final a = TextEditingController();
    final b = TextEditingController();
    final bn = FocusNode();
    await tester.pumpWidget(_app(a, b, bn));
    await tester.pump();

    // Down from the button: the email field is highlighted, no keyboard.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(tester.testTextInput.hasAnyClients, isFalse);

    // OK: the keyboard opens and typing works.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(tester.testTextInput.isVisible, isTrue);
    tester.testTextInput.enterText('me@test.it');
    await tester.pump();
    expect(a.text, 'me@test.it');

    // "Next" on the keyboard moves to the password with the keyboard open.
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(bn.hasPrimaryFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    // Back closes the keyboard and returns to D-Pad navigation.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(bn.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);

    // Up returns to the email field, OK opens the keyboard again.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(tester.testTextInput.isVisible, isTrue);

    // Tapping/clicking the password field also opens the keyboard.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).last);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(bn.hasPrimaryFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('TV login: keyboard opens on focus, Back keeps it closed', (
    tester,
  ) async {
    await _setTv(true);
    final a = TextEditingController();
    final b = TextEditingController();
    final bn = FocusNode();
    await tester.pumpWidget(_app(a, b, bn, openOnFocus: true));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('Phone: tapping the field opens the keyboard as before', (
    tester,
  ) async {
    await _setTv(false);
    final a = TextEditingController();
    final b = TextEditingController();
    final bn = FocusNode();
    await tester.pumpWidget(_app(a, b, bn));
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    await _setTv(true);
  });
}
