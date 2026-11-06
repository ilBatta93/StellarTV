import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/vpn_config_policy.dart';

const _priv = 'yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=';
const _pub = 'FgxaycYZ4t1kp4x7LDv60sczNTAl0h/d4pyyUNHhgBc=';

void main() {
  test('recognises WireGuard keys', () {
    expect(VpnConfigPolicy.isKey(_priv), isTrue);
    expect(VpnConfigPolicy.isKey(' $_pub '), isTrue);
    expect(VpnConfigPolicy.isKey('abc='), isFalse);
    expect(VpnConfigPolicy.isKey(''), isFalse);
  });

  test('reads a pasted configuration', () {
    final s = VpnConfigPolicy.parse('''
# from the VPN service
[Interface]
PrivateKey = $_priv
Address = 10.5.0.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = $_pub
AllowedIPs = 0.0.0.0/0
Endpoint = vpn.example.com:51820
''');
    expect(s.endpoint, 'vpn.example.com:51820');
    expect(s.privateKey, _priv);
  });

  test('explains what is missing', () {
    expect(
      () => VpnConfigPolicy.parse('nothing'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => VpnConfigPolicy.parse('[Interface]\nPrivateKey = $_priv\n'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Address'),
        ),
      ),
    );
    expect(
      () => VpnConfigPolicy.parse(
        '[Interface]\nPrivateKey = $_priv\nAddress = 10.0.0.2/32\n',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('builds a NordLynx configuration that parses back', () {
    final server = VpnConfigPolicy.nordServer([
      {
        'hostname': 'it455.nordvpn.com',
        'station': '187.13.213.142',
        'load': 8,
        'locations': [
          {
            'country': {
              'name': 'Italy',
              'city': {'name': 'Milan'},
            },
          },
        ],
        'technologies': [
          {'identifier': 'openvpn_udp', 'metadata': []},
          {
            'identifier': 'wireguard_udp',
            'metadata': [
              {'name': 'public_key', 'value': _pub},
            ],
          },
        ],
      },
    ])!;
    expect(server.label, 'it455 · Milan, Italy');
    final text = VpnConfigPolicy.nordConfig(privateKey: _priv, server: server);
    expect(text, contains('Endpoint = 187.13.213.142:51820'));
    expect(text, contains('AllowedIPs = 0.0.0.0/0, ::/0'));
    expect(VpnConfigPolicy.parse(text).privateKey, _priv);
  });

  test('skips servers without WireGuard', () {
    expect(
      VpnConfigPolicy.nordServer([
        {
          'hostname': 'x.nordvpn.com',
          'station': '1.2.3.4',
          'technologies': [
            {'identifier': 'openvpn_udp', 'metadata': []},
          ],
        },
      ]),
      isNull,
    );
    expect(VpnConfigPolicy.nordServer('bad'), isNull);
  });

  test('sorts countries by name', () {
    final list = VpnConfigPolicy.nordCountries([
      {'id': 106, 'name': 'Italy', 'code': 'IT'},
      {'id': 2, 'name': 'Albania', 'code': 'AL'},
      {'id': 'x'},
    ]);
    expect(list.map((c) => c.code), ['AL', 'IT']);
  });

  test('reads the phone package', () {
    final nord = VpnConfigPolicy.handoff({'kind': 'vpn', 'nord': ' abc '});
    expect(nord?.nordKey, 'abc');
    expect(nord?.config, isNull);
    final wg = VpnConfigPolicy.handoff({'kind': 'vpn', 'wg': '[Interface]'});
    expect(wg?.config, '[Interface]');
    expect(VpnConfigPolicy.handoff({'kind': 'xtream', 'nord': 'x'}), isNull);
    expect(VpnConfigPolicy.handoff({'kind': 'vpn'}), isNull);
    expect(VpnConfigPolicy.handoff('vpn'), isNull);
  });
}
