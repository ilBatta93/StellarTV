import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/player_settings.dart';
import 'package:stellar_tv/services/key_handoff.dart';

void main() {
  test('live streams default to the classic VLC user agent', () {
    expect(effectiveStreamUserAgent(''), 'VLC/3.0.20 LibVLC/3.0.20');
    expect(effectiveStreamUserAgent('StellarTV/1.0'), 'VLC/3.0.20 LibVLC/3.0.20');
    expect(effectiveStreamUserAgent('okhttp/4.12.0'), 'okhttp/4.12.0');
  });
  test('Xtream details from the phone are shape-checked', () {
    final x = XtreamHandoff.parse(
        '{"kind":"xtream","host":"http://a.tv:80","username":"u","password":"p"}');
    expect(x?.server, 'http://a.tv:80');
    expect(XtreamHandoff.parse('STV1-abc'), isNull);
    expect(XtreamHandoff.parse('{"kind":"xtream","host":"ftp://a","username":"u","password":"p"}'), isNull);
  });
}
