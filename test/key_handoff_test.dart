import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/key_handoff.dart';

void main() {
  test('opens the package sealed by the companion site', () async {
    final tv = await X25519().newKeyPairFromSeed(List.filled(32, 7));
    final key = await KeyHandoff.open(
      tv,
      'ABC234',
      'V9tLNZ8jrl4Ubk4lEgVnBHIlBjSMFQwUdT0Mkz0E1CE',
      'AQEBAQEBAQEBAQEB',
      'pf8R-0inPwvdLkIle7JfwY_NcUgvgvJThGTg',
    );
    expect(key, 'STV1-secret');
  });
  test('rejects a different code', () async {
    final tv = await X25519().newKeyPairFromSeed(List.filled(32, 7));
    expect(
      KeyHandoff.open(
        tv,
        'ABC235',
        'V9tLNZ8jrl4Ubk4lEgVnBHIlBjSMFQwUdT0Mkz0E1CE',
        'AQEBAQEBAQEBAQEB',
        'pf8R-0inPwvdLkIle7JfwY_NcUgvgvJThGTg',
      ),
      throwsA(anything),
    );
  });
  test('codes use 6 unambiguous characters', () {
    for (var i = 0; i < 50; i++) {
      expect(
        RegExp(r'^[A-HJ-NP-Z2-9]{6}$').hasMatch(KeyHandoff.newCode()),
        isTrue,
      );
    }
  });
}
