import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/device_identity.dart';
import 'package:stellar_tv/services/remote_signout_service.dart';

void main() {
  test('device label keeps type, platform and a clean model', () {
    expect(
      DeviceIdentity.format(
        version: '3.3.11',
        kind: 'tv',
        platform: 'Fire TV',
        model: 'Amazon AFTKA;)',
      ),
      'StellarTV/3.3.11 (kind=tv; platform=Fire TV; model=Amazon AFTKA; cloud=2)',
    );
  });

  test('session id is read from the access token', () {
    String seg(Map<String, Object> m) =>
        base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    final token = '${seg({'alg': 'HS256'})}.${seg({'session_id': 'abc'})}.sig';
    expect(RemoteSignoutService.sessionIdFromToken(token), 'abc');
    expect(RemoteSignoutService.sessionIdFromToken('bad'), isNull);
  });
}
