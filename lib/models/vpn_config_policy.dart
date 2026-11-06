/// Pure rules for the personal VPN (WireGuard): reading a configuration the
/// user pastes, building one from NordVPN server data, and the short summary
/// shown in the app. No I/O here.
class VpnConfigPolicy {
  VpnConfigPolicy._();

  /// NordLynx (NordVPN's WireGuard) fixed values: every account uses this
  /// tunnel address and the NordVPN resolvers.
  static const nordAddress = '10.5.0.2/32';
  static const nordDns = ['103.86.96.100', '103.86.99.100'];
  static const nordPort = 51820;

  static final _key = RegExp(r'^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw480]=$');

  /// True for a WireGuard key (32 bytes in base64).
  static bool isKey(String value) => _key.hasMatch(value.trim());

  /// Reads a wg-quick style configuration. Returns the summary, or throws a
  /// [FormatException] with a message for the user.
  static VpnConfigSummary parse(String text) {
    String? section;
    final iface = <String, String>{};
    final peers = <Map<String, String>>[];
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.split('#').first.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1).trim().toLowerCase();
        if (section == 'peer') peers.add({});
        continue;
      }
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim().toLowerCase();
      final value = line.substring(eq + 1).trim();
      if (section == 'interface') iface[key] = value;
      if (section == 'peer') peers.last[key] = value;
    }
    if (iface.isEmpty) {
      throw const FormatException('Manca la sezione [Interface]');
    }
    if (!isKey(iface['privatekey'] ?? '')) {
      throw const FormatException('Chiave privata mancante o non valida');
    }
    if ((iface['address'] ?? '').isEmpty) {
      throw const FormatException('Manca l\'indirizzo (Address)');
    }
    if (peers.isEmpty) {
      throw const FormatException('Manca la sezione [Peer]');
    }
    final peer = peers.first;
    if (!isKey(peer['publickey'] ?? '')) {
      throw const FormatException('Chiave pubblica del server non valida');
    }
    final endpoint = peer['endpoint'] ?? '';
    if (!endpoint.contains(':')) {
      throw const FormatException('Manca l\'indirizzo del server (Endpoint)');
    }
    if ((peer['allowedips'] ?? '').isEmpty) {
      throw const FormatException('Manca AllowedIPs');
    }
    return VpnConfigSummary(
      endpoint: endpoint,
      privateKey: iface['privatekey']!.trim(),
    );
  }

  /// Configuration for one NordVPN server. All traffic of the tunnel goes
  /// through it; IPv6 is routed into the tunnel too, so it cannot bypass it
  /// (NordLynx has no IPv6: those connections fall back to IPv4).
  static String nordConfig({
    required String privateKey,
    required NordServer server,
  }) {
    return [
      '[Interface]',
      'PrivateKey = ${privateKey.trim()}',
      'Address = $nordAddress',
      'DNS = ${nordDns.join(', ')}',
      '',
      '[Peer]',
      'PublicKey = ${server.publicKey}',
      'AllowedIPs = 0.0.0.0/0, ::/0',
      'Endpoint = ${server.ip}:$nordPort',
      'PersistentKeepalive = 25',
      '',
    ].join('\n');
  }

  /// First usable server of a NordVPN recommendations answer, or `null`.
  static NordServer? nordServer(Object? json) {
    if (json is! List) return null;
    for (final item in json) {
      if (item is! Map) continue;
      final ip = item['station'];
      final host = item['hostname'];
      if (ip is! String || ip.isEmpty || host is! String) continue;
      String? key;
      for (final tech in (item['technologies'] as List?) ?? const []) {
        if (tech is! Map || tech['identifier'] != 'wireguard_udp') continue;
        for (final meta in (tech['metadata'] as List?) ?? const []) {
          if (meta is Map && meta['name'] == 'public_key') {
            key = meta['value'] as String?;
          }
        }
      }
      if (key == null || !isKey(key)) continue;
      String? city;
      String? country;
      final locations = item['locations'];
      if (locations is List && locations.isNotEmpty) {
        final loc = locations.first;
        if (loc is Map && loc['country'] is Map) {
          final c = loc['country'] as Map;
          country = c['name'] as String?;
          if (c['city'] is Map) city = (c['city'] as Map)['name'] as String?;
        }
      }
      return NordServer(
        hostname: host,
        ip: ip,
        publicKey: key,
        city: city,
        country: country,
        load: item['load'] is int ? item['load'] as int : null,
      );
    }
    return null;
  }

  /// Phone-to-TV package (mode `v`, twin of `vpnPayload` in the site's
  /// `keyHandoff.ts`): `{"kind":"vpn","nord":"<access key>"}` or
  /// `{"kind":"vpn","wg":"<configuration>"}`. `null` when not valid.
  static VpnHandoff? handoff(Object? json) {
    if (json is! Map || json['kind'] != 'vpn') return null;
    final nord = json['nord'];
    if (nord is String && nord.trim().isNotEmpty) {
      return VpnHandoff(nordKey: nord.trim());
    }
    final wg = json['wg'];
    if (wg is String && wg.trim().isNotEmpty) {
      return VpnHandoff(config: wg.trim());
    }
    return null;
  }

  /// Countries of the NordVPN list, sorted by name.
  static List<NordCountry> nordCountries(Object? json) {
    if (json is! List) return const [];
    final out = <NordCountry>[];
    for (final item in json) {
      if (item is! Map) continue;
      final id = item['id'];
      final name = item['name'];
      final code = item['code'];
      if (id is! int || name is! String || code is! String) continue;
      out.add(NordCountry(id: id, name: name, code: code));
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }
}

class VpnHandoff {
  const VpnHandoff({this.nordKey, this.config});

  final String? nordKey;
  final String? config;
}

class VpnConfigSummary {
  const VpnConfigSummary({required this.endpoint, required this.privateKey});

  /// `host:port` of the VPN server.
  final String endpoint;
  final String privateKey;
}

class NordServer {
  const NordServer({
    required this.hostname,
    required this.ip,
    required this.publicKey,
    this.city,
    this.country,
    this.load,
  });

  final String hostname;
  final String ip;
  final String publicKey;
  final String? city;
  final String? country;
  final int? load;

  /// «it455 · Milan, Italy».
  String get label {
    final name = hostname.split('.').first;
    final place = [city, country].whereType<String>().join(', ');
    return place.isEmpty ? name : '$name · $place';
  }
}

class NordCountry {
  const NordCountry({required this.id, required this.name, required this.code});

  final int id;
  final String name;
  final String code;
}
