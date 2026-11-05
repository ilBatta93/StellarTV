import 'dart:typed_data';

/// A DNS-over-HTTPS resolver the app can use instead of the system DNS.
///
/// [bootstrap] are IP literals of the resolver itself, so reaching it never
/// depends on the system DNS it replaces. TLS still verifies [host].
class DnsResolverPreset {
  final String id;
  final String label;
  final String description;
  final String host;
  final String path;
  final List<String> bootstrap;

  const DnsResolverPreset({
    required this.id,
    required this.label,
    required this.description,
    required this.host,
    this.path = '/dns-query',
    this.bootstrap = const [],
  });

  Uri get endpoint => Uri.https(host, path);
}

/// Pure DNS settings: presets, the stored choice and the RFC 8484 wire format.
class DnsResolverPolicy {
  DnsResolverPolicy._();

  /// The system resolver: the app does not change anything.
  static const systemId = 'system';

  /// A user supplied DNS-over-HTTPS address.
  static const customId = 'custom';

  /// Default for new and existing installs: a public resolver that answers
  /// every name as published, without filtering lists.
  static const defaultId = 'adguard_unfiltered';

  // Every preset must answer DNS-over-HTTPS over HTTP/1.1: the Dart client
  // does not speak HTTP/2 (Mullvad and Quad9 answer only HTTP/2).
  static const presets = <DnsResolverPreset>[
    DnsResolverPreset(
      id: 'adguard_unfiltered',
      label: 'AdGuard senza filtri',
      description: 'Nessun blocco, nessun registro delle richieste',
      host: 'unfiltered.adguard-dns.com',
      bootstrap: ['94.140.14.140', '94.140.14.141'],
    ),
    DnsResolverPreset(
      id: 'controld_unfiltered',
      label: 'Control D senza filtri',
      description: 'Nessun blocco, rete globale',
      host: 'freedns.controld.com',
      path: '/p0',
      bootstrap: ['76.76.2.0', '76.76.10.0'],
    ),
    DnsResolverPreset(
      id: 'dnssb',
      label: 'DNS.SB',
      description: 'Nessun blocco, attento alla privacy',
      host: 'doh.dns.sb',
      bootstrap: ['185.222.222.222', '45.11.45.11'],
    ),
    DnsResolverPreset(
      id: 'cloudflare',
      label: 'Cloudflare 1.1.1.1',
      description: 'Molto veloce',
      host: 'cloudflare-dns.com',
      bootstrap: ['1.1.1.1', '1.0.0.1'],
    ),
    DnsResolverPreset(
      id: 'google',
      label: 'Google Public DNS',
      description: 'Molto diffuso',
      host: 'dns.google',
      bootstrap: ['8.8.8.8', '8.8.4.4'],
    ),
  ];

  static DnsResolverPreset? presetById(String id) {
    for (final p in presets) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The resolver for a stored choice. `null` means the system DNS.
  /// An unknown id (an old or removed preset) falls back to the default.
  static DnsResolverPreset? resolve(String? id, {String? customUrl}) {
    final choice = id ?? defaultId;
    if (choice == systemId) return null;
    if (choice == customId) {
      final custom = parseCustomUrl(customUrl);
      return custom ?? presetById(defaultId);
    }
    return presetById(choice) ?? presetById(defaultId);
  }

  /// A custom resolver must be an https address with a host. The path
  /// defaults to `/dns-query`.
  static DnsResolverPreset? parseCustomUrl(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    if (uri.hasPort && uri.port != 443) return null;
    final path = uri.path.isEmpty || uri.path == '/' ? '/dns-query' : uri.path;
    return DnsResolverPreset(
      id: customId,
      label: 'Personalizzato',
      description: uri.host,
      host: uri.host,
      path: path,
      bootstrap: _isIpLiteral(uri.host) ? [uri.host] : const [],
    );
  }

  /// Names that never go to a public resolver.
  static bool bypasses(String host) {
    final h = host.toLowerCase();
    if (h.isEmpty || _isIpLiteral(h)) return true;
    if (h == 'localhost' || h.endsWith('.localhost')) return true;
    if (h.endsWith('.local') || h.endsWith('.lan') || h.endsWith('.home')) {
      return true;
    }
    if (h.endsWith('.internal') || h.endsWith('.home.arpa')) return true;
    // A bare name (no dot) is a local network device.
    return !h.contains('.');
  }

  static bool _isIpLiteral(String host) {
    final h = host.startsWith('[') && host.endsWith(']')
        ? host.substring(1, host.length - 1)
        : host;
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(h)) return true;
    return h.contains(':') && RegExp(r'^[0-9a-fA-F:.]+$').hasMatch(h);
  }

  /// Cache lifetime for an answer: the record TTL, bounded so a tiny TTL does
  /// not hammer the resolver and a huge one does not pin a moved server.
  static Duration cacheFor(int ttlSeconds) =>
      Duration(seconds: ttlSeconds.clamp(60, 3600));

  /// Record types used by the app.
  static const typeA = 1;
  static const typeAaaa = 28;

  /// RFC 8484 wire-format query (id 0, recursion desired).
  static Uint8List encodeQuery(String name, int type) {
    final out = BytesBuilder();
    out.add(const [0, 0, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0]);
    final clean = name.endsWith('.')
        ? name.substring(0, name.length - 1)
        : name;
    for (final label in clean.split('.')) {
      final bytes = label.codeUnits;
      if (bytes.isEmpty || bytes.length > 63) {
        throw FormatException('Nome non valido: $name');
      }
      out.addByte(bytes.length);
      out.add(bytes);
    }
    out.addByte(0);
    out.add([type >> 8, type & 0xff, 0, 1]);
    return out.toBytes();
  }

  /// Parses a wire-format answer. Returns addresses of [type] (raw bytes) and
  /// the smallest TTL among them. Throws [FormatException] on a malformed
  /// message or a server failure; an empty list means "no such record".
  static DnsAnswer decodeAnswer(Uint8List msg, int type) {
    if (msg.length < 12) throw const FormatException('Risposta DNS corta');
    final data = ByteData.sublistView(msg);
    final flags = data.getUint16(2);
    final rcode = flags & 0x0f;
    // 3 = NXDOMAIN: a real "does not exist", not a resolver failure.
    if (rcode == 3) return const DnsAnswer([], 0);
    if (rcode != 0) throw FormatException('Errore DNS $rcode');
    final qd = data.getUint16(4);
    final an = data.getUint16(6);
    var offset = 12;
    for (var i = 0; i < qd; i++) {
      offset = _skipName(msg, offset) + 4;
    }
    final addresses = <Uint8List>[];
    int? minTtl;
    for (var i = 0; i < an; i++) {
      offset = _skipName(msg, offset);
      if (offset + 10 > msg.length) {
        throw const FormatException('Risposta DNS troncata');
      }
      final rtype = data.getUint16(offset);
      final ttl = data.getUint32(offset + 4);
      final len = data.getUint16(offset + 8);
      offset += 10;
      if (offset + len > msg.length) {
        throw const FormatException('Risposta DNS troncata');
      }
      final wanted = type == typeA ? 4 : 16;
      if (rtype == type && len == wanted) {
        addresses.add(Uint8List.fromList(msg.sublist(offset, offset + len)));
        minTtl = minTtl == null || ttl < minTtl ? ttl : minTtl;
      }
      offset += len;
    }
    return DnsAnswer(addresses, minTtl ?? 0);
  }

  static int _skipName(Uint8List msg, int offset) {
    while (true) {
      if (offset >= msg.length) {
        throw const FormatException('Nome DNS troncato');
      }
      final len = msg[offset];
      if (len == 0) return offset + 1;
      if (len & 0xc0 == 0xc0) return offset + 2;
      offset += len + 1;
    }
  }
}

class DnsAnswer {
  final List<Uint8List> addresses;
  final int ttlSeconds;

  const DnsAnswer(this.addresses, this.ttlSeconds);
}
