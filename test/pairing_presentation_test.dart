import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/screens/tv_pairing_screen.dart';
import 'package:stellar_tv/services/tv_pairing_service.dart';
import 'package:stellar_tv/theme/app_theme.dart';

class DemoPair extends TvPairingService {
  DemoPair(super.client);
  @override
  Future<TvPairing> create({String deviceName = 'TV'}) async => const TvPairing(
    code: 'ABC123',
    secret: 'demo',
    url: 'https://stellartv.vercel.app/collega?code=ABC123',
    expiresIn: 600,
  );
  @override
  Future<String?> pollToken(TvPairing pairing) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(390, 844),
  ]) {
    testWidgets('QR presentation ${size.width}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final family in ['Sora', 'Manrope', 'MaterialIcons']) {
        final loader = FontLoader(family)
          ..addFont(
            rootBundle.load(
              family == 'MaterialIcons'
                  ? 'fonts/MaterialIcons-Regular.otf'
                  : 'assets/fonts/$family.ttf',
            ),
          );
        await loader.load();
      }
      final client = SupabaseClient('https://example.test', 'test');
      final key = GlobalKey();
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme(),
            home: RepaintBoundary(
              key: key,
              child: TvPairingScreen(service: DemoPair(client)),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final boundary = key.currentContext?.findRenderObject();
      if (boundary is RenderRepaintBoundary) {
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          if (bytes != null) {
            await Directory('/tmp/stv').create(recursive: true);
            await File('/tmp/stv/qr-${size.width.toInt()}.png')
                .writeAsBytes(bytes.buffer.asUint8List());
          }
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      client.auth.stopAutoRefresh();
    });
  }
}
