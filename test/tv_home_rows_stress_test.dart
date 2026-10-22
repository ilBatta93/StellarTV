import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/image_warmup_service.dart';
import 'package:stellar_tv/widgets/tv_home_rows.dart';

Widget _row(int i) => Row(
  children: [
    for (var j = 0; j < 4; j++)
      Focus(
        autofocus: i == 0 && j == 0,
        child: SizedBox(width: 60, height: 60, child: Text('$i-$j')),
      ),
  ],
);

class _Host extends StatefulWidget {
  const _Host({super.key});
  @override
  State<_Host> createState() => HostState();
}

class HostState extends State<_Host> {
  int count = 8;
  void change(int c) => setState(() => count = c);
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: TvHomeRows(sections: [for (var i = 0; i < count; i++) _row(i)]),
    ),
  );
}

void main() {
  testWidgets('rapid D-Pad while Home sections change never throws', (
    tester,
  ) async {
    final key = GlobalKey<HostState>();
    await tester.pumpWidget(_Host(key: key));
    await tester.pump();
    for (var i = 0; i < 120; i++) {
      final down = i % 5 != 4;
      await tester.sendKeyEvent(
        down ? LogicalKeyboardKey.arrowDown : LogicalKeyboardKey.arrowUp,
      );
      // Background work reshapes Home mid-navigation.
      if (i % 7 == 0) key.currentState?.change(3 + (i % 9));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(FocusManager.instance.primaryFocus, isNotNull);
  });

  testWidgets('last row survives shrink, empty list and refill', (
    tester,
  ) async {
    final key = GlobalKey<HostState>();
    await tester.pumpWidget(_Host(key: key));
    await tester.pump();
    for (var i = 0; i < 7; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    final host = key.currentState;
    expect(host, isNotNull);
    if (host == null) return;
    host.change(2);
    await tester.pumpAndSettle();
    final scroll = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(scroll.pixels, lessThanOrEqualTo(scroll.maxScrollExtent));
    host.change(0);
    await tester.pumpAndSettle();
    host.change(4);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('pressure mode retains every vertical remote destination', (
    tester,
  ) async {
    TvImageMemoryGuard.reducedRendering.value = true;
    addTearDown(() => TvImageMemoryGuard.reducedRendering.value = false);
    await tester.pumpWidget(const _Host());
    await tester.pumpAndSettle();
    for (var i = 1; i < 8; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      expect(focusedContext, isNotNull);
      if (focusedContext == null) return;
      final label = find.descendant(
        of: find.byWidget(focusedContext.widget),
        matching: find.text('$i-0'),
      );
      expect(label, findsOneWidget);
    }
    for (var i = 6; i >= 0; i--) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      expect(focusedContext, isNotNull);
      if (focusedContext == null) return;
      expect(
        find.descendant(
          of: find.byWidget(focusedContext.widget),
          matching: find.text('$i-0'),
        ),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  test('background image work yields while the remote is moving', () async {
    RemoteNavigation.note();
    expect(RemoteNavigation.moving, isTrue);
    final start = DateTime.now();
    await RemoteNavigation.idle();
    expect(RemoteNavigation.moving, isFalse);
    expect(
      DateTime.now().difference(start).inMilliseconds,
      greaterThanOrEqualTo(300),
    );
  });
}
