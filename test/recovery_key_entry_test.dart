import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/widgets/recovery_key_entry.dart';
import 'package:stellar_tv/widgets/tv_text_field.dart';

void main() {
  testWidgets('a missing key explains itself and shows a field', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecoveryKeyEntry(
            presence: RecoveryKeyPresence.missing,
            controller: controller,
          ),
        ),
      ),
    );
    expect(find.text(recoveryKeyExplanation), findsOneWidget);
    expect(find.text('Incolla la chiave STV1-…'), findsOneWidget);
    expect(find.byType(TvTextField), findsOneWidget);
    expect(find.text(recoveryKeySavedNotice), findsNothing);
  });

  testWidgets('a saved key is announced and not requested again', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecoveryKeyEntry(presence: RecoveryKeyPresence.saved),
        ),
      ),
    );
    expect(find.text(recoveryKeyExplanation), findsOneWidget);
    expect(find.text(recoveryKeySavedNotice), findsOneWidget);
    expect(find.byType(TvTextField), findsNothing);
  });
}
