import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/widgets/brand_intro.dart';

// The intro sky is drawn in one pass on the TV; it must look like the three
// gradient nebulas it replaces.
void main() {
  Future<Uint8List> render(
    WidgetTester tester,
    double progress, {
    required bool onePass,
  }) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: BrandIntroBackdrop(progress: progress, onePass: onePass),
      ),
    );
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      // Scaled like the TV's screen: the shader must use canvas coordinates.
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  testWidgets('the one-pass sky matches the gradient sky', (tester) async {
    tester.view.physicalSize = const Size(480, 270);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(BrandIntroBackdrop.preload);
    expect(BrandIntroBackdrop.skyReady, isTrue);
    for (final progress in [0.1, 0.5, 1.0]) {
      final gradients = await render(tester, progress, onePass: false);
      final onePass = await render(tester, progress, onePass: true);
      expect(onePass.length, gradients.length);
      var worst = 0;
      for (var i = 0; i < onePass.length; i++) {
        final d = (onePass[i] - gradients[i]).abs();
        if (d > worst) worst = d;
      }
      // Rounding and dithering only: a few levels out of 255.
      expect(worst, lessThanOrEqualTo(4), reason: 'progress $progress');
    }
  });
}
