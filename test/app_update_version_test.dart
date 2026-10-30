import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/app_update_service.dart';

void main() {
  int b(String v) => AppUpdateService.buildOf(v);

  test(
    'patch successiva è più nuova',
    () => expect(b('3.1.4') > b('3.1.3'), isTrue),
  );
  test(
    'minor nuova batte patch alta',
    () => expect(b('v3.1.0') > b('3.0.12'), isTrue),
  );
  test('major nuova', () {
    expect(b('4.0.0') > b('3.9.50'), isTrue);
    expect(b('5.0.0') > b('4.2.1'), isTrue);
  });
  test('prefisso v ignorato', () => expect(b('v3.1.3'), b('3.1.3')));
  test('uguale o più vecchia non aggiorna', () {
    expect(b('3.1.3') > b('3.1.3'), isFalse);
    expect(b('3.0.12') > b('3.1.3'), isFalse);
  });
}
