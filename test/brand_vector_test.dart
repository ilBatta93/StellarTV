import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:stellar_tv/widgets/brand_logo.dart';
import 'package:stellar_tv/widgets/brand_intro.dart';

void main() {
  testWidgets('approved vectors render in existing brand envelopes', (tester) async {
    final key = GlobalKey();
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(backgroundColor: const Color(0xff101113), body: RepaintBoundary(key: key, child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [BrandLogo(size: 46), SizedBox(height: 20), BrandMark(size: 96), SizedBox(height: 20), BrandName(height: 50), SizedBox(height: 20), SizedBox(width: 640, child: BrandIntro(progress: 1))]))))));
    await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 200)); });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.descendant(of: find.byType(BrandLogo), matching: find.byType(SvgPicture)), findsNWidgets(3));
    expect(tester.getSize(find.byType(BrandLogo)).height, 46 * 1.35);
    expect(tester.getSize(find.byType(BrandLogo)).width, closeTo(46 * 1.35 * 1992.1 / 514, .001));
    expect(tester.getSize(find.byType(BrandIntro)).height, closeTo(640 * 514 / 1992.1, .01));
    final boundary = key.currentContext?.findRenderObject();
    if (boundary is RenderRepaintBoundary) {
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data != null) { await Directory('/tmp/branding').create(recursive: true); await File('/tmp/branding/flutter-brand.png').writeAsBytes(data.buffer.asUint8List()); }
      });
    }
  });
}
