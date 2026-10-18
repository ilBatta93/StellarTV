import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/stream_probe.dart';
import 'package:stellar_tv/services/live_diagnostics_log.dart';

void main() {
  test('MPEG-TS sync is recognised only on real packets', () {
    expect(StreamProbe.tsSync(List.generate(188 * 5, (i) => i % 188 == 0 ? 0x47 : 0)), isTrue);
    expect(StreamProbe.tsSync(List.filled(188 * 5, 0x20)), isFalse);
  });
  test('HTTP status is read from player errors', () {
    expect(StreamProbe.statusIn('Response code: 403'), 403);
    expect(StreamProbe.statusIn('HTTP 509 bandwidth'), 509);
    expect(StreamProbe.statusIn('decoder failed'), isNull);
  });
  test('Probe results enter the report, hosts never do', () {
    final log = LiveDiagnosticsLog()..enabled = true;
    log.add('stream_probe', data: {'probeStatus': 200, 'probeKind': 'm3u8', 'host': 'x.example'});
    final r = log.report({});
    expect(r.contains('"probeStatus": 200'), isTrue);
    expect(r.contains('x.example'), isFalse);
  });
}
