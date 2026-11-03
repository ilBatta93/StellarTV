import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/key_handoff.dart';

/// Mirrors Android's native HMAC: an empty key is an error, with no fallback.
class _EmptyKeyHmacRejecting extends DartCryptography {
  @override
  Hmac hmac(HashAlgorithm hashAlgorithm) => _RejectingHmac(hashAlgorithm);
}

class _RejectingHmac extends DartHmac {
  _RejectingHmac(super.hashAlgorithm);
  @override
  Future<Mac> calculateMac(
    List<int> bytes, {
    required SecretKey secretKey,
    List<int> nonce = const <int>[],
    List<int> aad = const <int>[],
  }) async {
    if ((await secretKey.extractBytes()).isEmpty) {
      throw StateError('Empty key');
    }
    return super.calculateMac(bytes, secretKey: secretKey, nonce: nonce);
  }
}

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
  test(
    'opens the package when the platform HMAC rejects an empty salt',
    () async {
      // Android's native HMAC (cryptography_flutter) throws on the empty HKDF
      // salt the site uses; the handoff must not depend on it.
      final previous = Cryptography.instance;
      Cryptography.instance = _EmptyKeyHmacRejecting();
      addTearDown(() => Cryptography.instance = previous);
      final tv = await X25519().newKeyPairFromSeed(List.filled(32, 7));
      final key = await KeyHandoff.open(
        tv,
        'ABC234',
        'V9tLNZ8jrl4Ubk4lEgVnBHIlBjSMFQwUdT0Mkz0E1CE',
        'AQEBAQEBAQEBAQEB',
        'pf8R-0inPwvdLkIle7JfwY_NcUgvgvJThGTg',
      );
      expect(key, 'STV1-secret');
    },
  );
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
