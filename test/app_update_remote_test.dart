import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/services/app_update_service.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/widgets/tv_focusable.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('stellartv/device'),
          (call) async => call.method == 'isTv',
        );
    await DeviceTypeService.initialize();
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('stellartv/device'),
          (call) async => false,
        );
    await DeviceTypeService.initialize();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('stellartv/device'),
          null,
        );
  });

  Future<void> open(WidgetTester tester, String notes) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => UiSettings(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  AppUpdateService.showReleaseDialog(
                    context,
                    AppRelease(
                      '9.0.0',
                      9000000,
                      notes,
                      'https://example.com/test.apk',
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  FocusNode? actionNode(WidgetTester tester, String label) => tester
      .widget<TvFocusable>(
        find.ancestor(of: find.text(label), matching: find.byType(TvFocusable)),
      )
      .focusNode;

  testWidgets('update starts focused and notes enter at top', (tester) async {
    await open(tester, List.generate(80, (i) => 'Change $i').join('\n'));
    expect(actionNode(tester, 'Aggiorna ora')?.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller;
    expect(scroll?.offset, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(scroll?.offset, 56);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(scroll?.offset, 0);
  });

  testWidgets('end returns to update then later; reentry resets notes', (
    tester,
  ) async {
    await open(tester, List.generate(40, (i) => 'Change $i').join('\n'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    final scroll = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller;
    expect(scroll, isNotNull);
    if (scroll == null) return;
    for (var i = 0; i < 40; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      if (actionNode(tester, 'Aggiorna ora')?.hasFocus ?? false) break;
    }
    expect(scroll.offset, scroll.position.maxScrollExtent);
    expect(actionNode(tester, 'Aggiorna ora')?.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(actionNode(tester, 'Più tardi')?.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(scroll.offset, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty notes leave both actions reachable', (tester) async {
    await open(tester, '');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(actionNode(tester, 'Aggiorna ora')?.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(actionNode(tester, 'Più tardi')?.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
