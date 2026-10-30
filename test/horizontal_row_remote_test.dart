import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/widgets/section_row.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  for (final count in [50, 100]) {
    testWidgets('Remote reaches all $count titles and keeps selection visible', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final nodes = List.generate(
        count,
        (i) => FocusNode(debugLabel: 'card $i'),
      );
      final below = FocusNode(debugLabel: 'below');
      final vertical = ScrollController();
      var bannerIndex = -1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: vertical,
              children: [
                const SizedBox(height: 80),
                const Text('Recenti'),
                HorizontalRow(
                  height: 200,
                  spacing: 20,
                  itemCount: count,
                  itemBuilder: (_, i) => Focus(
                    focusNode: nodes[i],
                    // Reproduce Home: a custom banner/heading callback disables
                    // the generic poster reveal, but the row must still scroll.
                    onFocusChange: (focused) {
                      if (focused) bannerIndex = i;
                    },
                    child: SizedBox(
                      key: ValueKey('card-$i'),
                      width: 112,
                      height: 180,
                      child: Text('Titolo $i'),
                    ),
                  ),
                ),
                Focus(
                  focusNode: below,
                  child: const SizedBox(width: 112, height: 80),
                ),
                const SizedBox(height: 600),
              ],
            ),
          ),
        ),
      );
      nodes.first.requestFocus();
      await tester.pump();
      await tester.pump();
      final top = vertical.offset;
      for (var i = 1; i < count; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        await tester.pump();
        expect(nodes[i].hasPrimaryFocus, isTrue, reason: 'Title $i reachable');
        expect(bannerIndex, i);
        final rect = tester.getRect(find.byKey(ValueKey('card-$i')));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(960));
        expect(vertical.offset, top);
      }
      // Repeated Right at the true end must not fall to the next row.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(nodes.last.hasPrimaryFocus, isTrue);
      for (var i = count - 2; i >= 0; i--) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        await tester.pump();
        expect(nodes[i].hasPrimaryFocus, isTrue);
        final rect = tester.getRect(find.byKey(ValueKey('card-$i')));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(960));
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(nodes.first.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(below.hasPrimaryFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      for (final node in nodes) {
        node.dispose();
      }
      below.dispose();
      vertical.dispose();
    });
  }

  testWidgets('Entering a row from above reveals an off-screen card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final nodes = List.generate(6, (i) => FocusNode(debugLabel: 'card $i'));
    final vertical = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: vertical,
            children: [
              const SizedBox(height: 700),
              HorizontalRow(
                height: 200,
                spacing: 20,
                itemCount: 6,
                itemBuilder: (_, i) => Focus(
                  focusNode: nodes[i],
                  child: SizedBox(
                    key: ValueKey('card-$i'),
                    width: 112,
                    height: 180,
                    child: Text('Titolo $i'),
                  ),
                ),
              ),
              const SizedBox(height: 600),
            ],
          ),
        ),
      ),
    );
    nodes.first.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(vertical.offset, greaterThan(0));
    final rect = tester.getRect(find.byKey(const ValueKey('card-0')));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(540.5));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    for (final node in nodes) {
      node.dispose();
    }
    vertical.dispose();
  });
}
