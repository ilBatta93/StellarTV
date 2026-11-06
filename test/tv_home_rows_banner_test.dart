import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/image_warmup_service.dart';
import 'package:stellar_tv/widgets/tv_home_rows.dart';

/// Home rows under the banner buttons, with the memory saving of 1 GB TV
/// sticks (rows off screen are not built).
void main() {
  late FocusNode button;
  late TvHomeRowsController rows;

  setUp(() {
    button = FocusNode(debugLabel: 'banner-button');
    rows = TvHomeRowsController();
    TvImageMemoryGuard.reducedRendering.value = true;
  });
  tearDown(() {
    TvImageMemoryGuard.reducedRendering.value = false;
  });

  Widget card(int row, int i) => Focus(
    debugLabel: 'card-$row-$i',
    child: SizedBox(width: 60, height: 60, child: Text('$row-$i')),
  );

  Widget home({bool exitTop = true}) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          Focus(
            focusNode: button,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.arrowDown) {
                return rows.focusCurrent()
                    ? KeyEventResult.handled
                    : KeyEventResult.ignored;
              }
              return KeyEventResult.ignored;
            },
            child: const SizedBox(height: 40, child: Text('Guarda')),
          ),
          Expanded(
            child: TvHomeRows(
              controller: rows,
              onExitTop: exitTop
                  ? () {
                      button.requestFocus();
                      return true;
                    }
                  : null,
              sections: [
                for (var r = 0; r < 4; r++)
                  _Late(
                    Row(children: [for (var i = 0; i < 4; i++) card(r, i)]),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('moving between rows never lands on the banner button', (
    tester,
  ) async {
    await tester.pumpWidget(home());
    await tester.pumpAndSettle();
    // The banner button was focused once: it is in the page's history.
    button.requestFocus();
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(), 'card-0-0');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'card-0-1');
    for (var r = 1; r < 4; r++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(), 'card-$r-0');
    }
    for (var r = 2; r >= 0; r--) {
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(), r == 0 ? 'card-0-1' : 'card-$r-0');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('up from the first row reaches the banner, down comes back', (
    tester,
  ) async {
    await tester.pumpWidget(home());
    await tester.pumpAndSettle();
    button.requestFocus();
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'card-0-2');
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focused(), 'banner-button');
    // Back to the same card, not the one geometrically under the button.
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(), 'card-0-2');
  });

  testWidgets('without banner buttons up is left to the page', (tester) async {
    await tester.pumpWidget(home(exitTop: false));
    await tester.pumpAndSettle();
    rows.focusCurrent();
    await tester.pumpAndSettle();
    expect(focused(), 'card-0-0');
    // The rows let the key through: the page's own traversal moves on.
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focused(), 'banner-button');
  });
}

/// Like the Home cards, which wait for their artwork: the row gets its
/// focusable cards a frame after it is built.
class _Late extends StatefulWidget {
  const _Late(this.child);
  final Widget child;
  @override
  State<_Late> createState() => _LateState();
}

class _LateState extends State<_Late> {
  bool _ready = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? widget.child : const SizedBox(height: 60);
}
