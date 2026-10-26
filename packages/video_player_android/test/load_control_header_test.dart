import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_android/src/load_control_header.dart';

void main() {
  test('l header di load control viene letto e tolto dalle richieste', () {
    final headers = <String, String>{
      'User-Agent': 'StellarTV',
      exoLoadControlHeader: '1500,4000,500,1000,0,0,8388608',
    };
    final parsed = ExoLoadControlHeader.parse(takeExoLoadControlHeader(headers));
    expect(headers.keys, ['User-Agent']);
    expect(parsed, isNotNull);
    expect(parsed!.maxBufferMs, 4000);
    expect(parsed.backBufferRequiresSeekable, isFalse);
    expect(parsed.targetBufferBytes, 8388608);
    expect(ExoLoadControlHeader.parse('1,2,3'), isNull);
    expect(ExoLoadControlHeader.parse('1,2,3,4,-1,0,0'), isNull);
  });
}
