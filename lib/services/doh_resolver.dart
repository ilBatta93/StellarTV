import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/dns_resolver_policy.dart';

/// DNS-over-HTTPS resolver with an in-memory cache. Pure `dart:io`, so it
/// also runs inside the stream proxy isolate.
///
/// [lookup] never throws: an empty list means "use the system DNS", so a
/// blocked or slow resolver degrades to the old behaviour instead of breaking
/// the app.
class DohResolver {
  DohResolver(this.preset);

  final DnsResolverPreset preset;

  final _cache = <String, _CachedAnswer>{};
  final _inFlight = <String, Future<List<InternetAddress>>>{};
  HttpClient? _client;
  DateTime? _pausedUntil;

  static const _queryTimeout = Duration(seconds: 5);
  static const _bootstrapTimeout = Duration(seconds: 4);

  /// After a resolver failure the system DNS is used for a while, so a
  /// resolver that does not answer cannot slow every request down.
  static const _failurePause = Duration(seconds: 30);

  Future<List<InternetAddress>> lookup(String host) {
    final name = host.toLowerCase();
    if (DnsResolverPolicy.bypasses(name)) return Future.value(const []);
    final cached = _cache[name];
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      return Future.value(cached.addresses);
    }
    final paused = _pausedUntil;
    if (paused != null && paused.isAfter(DateTime.now())) {
      return Future.value(const []);
    }
    // A block body: returning the removed future would make it wait on itself.
    return _inFlight[name] ??= _resolve(name).whenComplete(() {
      _inFlight.remove(name);
    });
  }

  Future<List<InternetAddress>> _resolve(String name) async {
    try {
      final results = await Future.wait([
        _query(name, DnsResolverPolicy.typeA),
        _query(
          name,
          DnsResolverPolicy.typeAaaa,
        ).catchError((Object _) => const DnsAnswer([], 0)),
      ]);
      // IPv4 first: many home and TV networks have no working IPv6 route.
      final addresses = <InternetAddress>[
        for (final raw in results[0].addresses)
          InternetAddress.fromRawAddress(raw),
        for (final raw in results[1].addresses)
          InternetAddress.fromRawAddress(raw),
      ];
      final ttls = [
        for (final r in results)
          if (r.addresses.isNotEmpty) r.ttlSeconds,
      ];
      final ttl = ttls.isEmpty ? 60 : ttls.reduce((a, b) => a < b ? a : b);
      _cache[name] = _CachedAnswer(
        addresses,
        DateTime.now().add(DnsResolverPolicy.cacheFor(ttl)),
      );
      return addresses;
    } catch (_) {
      _pausedUntil = DateTime.now().add(_failurePause);
      return const [];
    }
  }

  Future<DnsAnswer> _query(String name, int type) async {
    final query = DnsResolverPolicy.encodeQuery(name, type);
    final dns = base64Url.encode(query).replaceAll('=', '');
    final uri = preset.endpoint.replace(queryParameters: {'dns': dns});
    final client = _client ??= _createClient();
    final request = await client.getUrl(uri).timeout(_queryTimeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/dns-message');
    final response = await request.close().timeout(_queryTimeout);
    if (response.statusCode != 200) {
      await response.drain<void>().catchError((_) {});
      throw HttpException('DNS ${response.statusCode}');
    }
    final builder = BytesBuilder(copy: false);
    await response.timeout(_queryTimeout).forEach(builder.add);
    return DnsResolverPolicy.decodeAnswer(builder.toBytes(), type);
  }

  HttpClient _createClient() {
    final client = HttpClient()
      ..connectionTimeout = _bootstrapTimeout
      ..idleTimeout = const Duration(seconds: 30)
      ..userAgent = null
      ..findProxy = ((_) => 'DIRECT');
    // Replaces any app-wide factory: the resolver is reached through its own
    // fixed addresses, never through the DNS it is replacing.
    client.connectionFactory = (uri, _, _) => _connectBootstrap(uri);
    return client;
  }

  Future<ConnectionTask<Socket>> _connectBootstrap(Uri uri) async {
    final addresses = [
      for (final ip in preset.bootstrap) ?InternetAddress.tryParse(ip),
    ];
    if (addresses.isEmpty) {
      // A custom resolver given by name: its own name uses the system DNS.
      return SecureSocket.startConnect(uri.host, uri.port);
    }
    return connectAddresses(
      addresses,
      uri.port,
      tlsHost: uri.host,
      timeout: _bootstrapTimeout,
    );
  }

  void close() {
    _client?.close(force: true);
    _client = null;
    _cache.clear();
  }

  /// Opens a socket to the first reachable address. With [tlsHost] the
  /// socket is upgraded to TLS, verifying the certificate for that name
  /// (also used for SNI), so connecting by IP keeps the usual security.
  static Future<ConnectionTask<Socket>> connectAddresses(
    List<InternetAddress> addresses,
    int port, {
    String? tlsHost,
    SecurityContext? context,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    var cancelled = false;
    ConnectionTask<Socket>? current;
    Future<Socket> connect() async {
      Object? lastError;
      for (final address in addresses) {
        if (cancelled) break;
        try {
          final task = await Socket.startConnect(address, port);
          current = task;
          final socket = await task.socket.timeout(
            timeout,
            onTimeout: () {
              task.cancel();
              throw SocketException('Connessione scaduta', port: port);
            },
          );
          if (tlsHost == null) return socket;
          return await SecureSocket.secure(
            socket,
            host: tlsHost,
            context: context,
          );
        } catch (e) {
          lastError = e;
        }
      }
      throw lastError ?? const SocketException('Connessione annullata');
    }

    return ConnectionTask.fromSocket(connect(), () {
      cancelled = true;
      current?.cancel();
    });
  }
}

class _CachedAnswer {
  final List<InternetAddress> addresses;
  final DateTime expires;

  _CachedAnswer(this.addresses, this.expires);
}
