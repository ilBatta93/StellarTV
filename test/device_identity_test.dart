import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/device_identity.dart';

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
}
