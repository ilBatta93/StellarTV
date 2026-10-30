import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/live_diagnostics_log.dart';

void main() {
  test('exports never include source hash, session or raw credentials', () {
    final log = LiveDiagnosticsLog()..enabled = true;
    log.add(
      'error',
      session: 'source-identity',
      data: {
        'stream': log.streamId('https://private/u/p'),
        'url': 'https://private/u/p',
        'message': 'password=secret',
        'category': 'network',
        'startupMs': 123,
      },
    );
    final report = log.report({'platform': 'android', 'token': 'secret'});
    expect(report, isNot(contains('source-identity')));
    expect(report, isNot(contains('https://private')));
    expect(report, isNot(contains('secret')));
    expect(report, isNot(contains('"stream"')));
    expect(report, contains('123'));
    expect(report, contains('network'));
  });
}
