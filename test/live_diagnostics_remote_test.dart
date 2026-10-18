import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/screens/live_diagnostics_screen.dart';
import '../lib/services/live_diagnostics_service.dart';
import '../lib/services/device_type_service.dart';
import '../lib/providers/ui_settings.dart';
import '../lib/widgets/tv_focusable.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'TV remote activates recording and reaches report upload and deletion',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const channel = MethodChannel('stellartv/device');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'isTv',
      );
      await DeviceTypeService.initialize();
      final service = LiveDiagnosticsService.instance;
      await tester.runAsync(service.initialize);
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => UiSettings(),
          child: const MaterialApp(home: LiveDiagnosticsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final toggle = find.ancestor(
        of: find.byType(SwitchListTile),
        matching: find.byType(TvFocusable),
      );
      expect(toggle, findsOneWidget);
      final ctx = tester.element(toggle);
      final focus = find
          .descendant(of: toggle, matching: find.byType(Focus))
          .first;
      final node = tester.widget<Focus>(focus).focusNode;
      // TvFocusable uses an internal Focus node when not supplied.
      if (node != null) {
        node.requestFocus();
      } else {
        FocusScope.of(ctx).nextFocus();
      }
      await tester.pumpAndSettle();
      // Explicitly focus the rendered stop rather than relying on geometry.
      final stop = Focus.of(
        tester.element(
          find.descendant(of: focus, matching: find.byType(ExcludeFocus)).first,
        ),
      );
      stop.requestFocus();
      await tester.pump();
      await tester.runAsync(() async {
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(service.enabled, true);
      for (final title in ['Invia al mio account', 'Cancella dati locali']) {
        final row = find.ancestor(
          of: find.text(title),
          matching: find.byType(TvFocusable),
        );
        expect(row, findsOneWidget);
        final child = find
            .descendant(of: row, matching: find.byType(ExcludeFocus))
            .first;
        Focus.of(tester.element(child)).requestFocus();
        await tester.pumpAndSettle();
        expect(Focus.of(tester.element(child)).hasFocus, true);
      }
      await tester.runAsync(() => service.setEnabled(false));
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    },
  );
}
