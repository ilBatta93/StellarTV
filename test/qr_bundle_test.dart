import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/key_handoff.dart';

void main() {
  test('QR bundle accepts list details and recovery key', () {
    final b = BundleHandoff.parse(
      '{"kind":"bundle","xtream":{"host":"http://h:80","username":"u","password":"p"},"key":"STV1-AB"}',
    );
    expect(b?.xtream?.server, 'http://h:80');
    expect(b?.key, 'STV1-AB');
  });
  test('QR bundle rejects empty or malformed payloads', () {
    expect(BundleHandoff.parse('{"kind":"bundle"}'), isNull);
    expect(BundleHandoff.parse('{"kind":"bundle","key":"abc"}'), isNull);
  });
}
