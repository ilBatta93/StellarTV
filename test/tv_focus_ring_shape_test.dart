import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/theme/app_theme.dart';
import 'package:stellar_tv/widgets/tv_focusable.dart';

Future<void> _setTv() async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('stellartv/device'),
        (call) async => true,
      );
  await DeviceTypeService.initialize();
  debugDefaultTargetPlatformOverride = null;
}

ShapeBorder _ringOf(WidgetTester tester, Key key) {
  final ring = tester.widget<Container>(
    find
        .descendant(of: find.byKey(key), matching: find.byType(Container))
        .first,
  );
  return (ring.foregroundDecoration! as ShapeDecoration).shape;
}

void main() {
  testWidgets('the focus ring takes the shape of the wrapped control', (
    tester,
  ) async {
    await _setTv();
    const pill = Key('pill');
    const icon = Key('icon');
    const card = Key('card');
    const wrapped = Key('wrapped');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(isTv: true),
        home: Scaffold(
          body: Column(
            children: [
              TvFocusable(
                key: pill,
                autofocus: true,
                onPressed: () {},
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('Guarda ora'),
                ),
              ),
              TvFocusable(
                key: wrapped,
                onPressed: () {},
                child: SizedBox(
                  width: 200,
                  child: ElevatedButton(
                    onPressed: () {},
                    child: const Text('Connetti'),
                  ),
                ),
              ),
              TvFocusable(
                key: icon,
                onPressed: () {},
                child: IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.search),
                ),
              ),
              TvFocusable(
                key: card,
                onPressed: () {},
                child: const SizedBox(width: 80, height: 40),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final focused = _ringOf(tester, pill) as StadiumBorder;
    // Light ring: an accent ring would vanish on the accent capsule.
    expect(focused.side.color, AppColors.textPrimary);
    expect(_ringOf(tester, icon), isA<CircleBorder>());
    // A button inside a layout wrapper (login "Connetti") is still a capsule.
    expect(_ringOf(tester, wrapped), isA<StadiumBorder>());
    expect(_ringOf(tester, card), isA<RoundedRectangleBorder>());
  });
}
