import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dns_resolver_policy.dart';
import 'dns_stream_proxy.dart';
import 'doh_resolver.dart';

/// App-wide DNS choice. With a resolver active:
/// - every Dart HTTP connection (catalog, guide, account, images) resolves
///   names through it (`HttpOverrides`);
/// - ExoPlayer receives it through the internal `X-StellarTV-Dns` header;
/// - mpv reaches plain-http streams through [DnsStreamProxy].
///
/// The choice stays on the device: it is a network setting, not a preference
/// synced to the cloud.
class DnsService extends ChangeNotifier {
  DnsService._();

  static final instance = DnsService._();

  static const _choiceKey = 'dns_resolver_v1';
  static const _customKey = 'dns_custom_url_v1';

  String _choice = DnsResolverPolicy.defaultId;
  String? _customUrl;
  DohResolver? _resolver;
  Future<DnsStreamProxy?>? _proxy;

  String get choice => _choice;
  String? get customUrl => _customUrl;

  /// The resolver in use, `null` for the system DNS.
  DnsResolverPreset? get active =>
      DnsResolverPolicy.resolve(_choice, customUrl: _customUrl);

  /// Reads the stored choice and routes Dart HTTP through it. Called once at
  /// startup, before any network client is created.
  Future<void> install() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _choice = prefs.getString(_choiceKey) ?? DnsResolverPolicy.defaultId;
      _customUrl = prefs.getString(_customKey);
    } catch (_) {}
    _rebuild();
    HttpOverrides.global = _DnsHttpOverrides(this);
  }

  Future<void> setChoice(String id, {String? customUrl}) async {
    _choice = id;
    if (customUrl != null) _customUrl = customUrl.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_choiceKey, _choice);
      if (_customUrl != null) await prefs.setString(_customKey, _customUrl!);
    } catch (_) {}
    _rebuild();
    notifyListeners();
  }

  void _rebuild() {
    _resolver?.close();
    final preset = active;
    _resolver = preset == null ? null : DohResolver(preset);
    final oldProxy = _proxy;
    _proxy = null;
    unawaited(oldProxy?.then((p) => p?.stop()).catchError((_) {}));
  }

  /// Addresses for [host] from the chosen resolver. Empty means "use the
  /// system DNS" (system choice, local name, or resolver unreachable).
  Future<List<InternetAddress>> lookup(String host) =>
      _resolver?.lookup(host) ?? Future.value(const []);

  /// Value of the internal ExoPlayer header: `endpoint|ip,ip`. Never sent to
  /// a stream server (the Java side removes it).
  String? get nativeHeaderValue {
    final preset = active;
    if (preset == null) return null;
    return '${preset.endpoint}|${preset.bootstrap.join(',')}';
  }

  /// `http-proxy` for mpv, started on first use. `null` with the system DNS
  /// or when the proxy cannot start (mpv then resolves as before).
  Future<String?> streamProxyUrl() async {
    final preset = active;
    if (preset == null) return null;
    final proxy = _proxy ??= DnsStreamProxy.start(preset)
        .then<DnsStreamProxy?>((p) => p)
        .catchError((Object _) => null);
    final started = await proxy;
    if (started == null) _proxy = null;
    return started?.url;
  }

  /// Resolves a known name with the chosen resolver, for the settings screen.
  /// Returns the time taken, or `null` when it did not answer.
  Future<Duration?> probe() async {
    final preset = active;
    if (preset == null) return null;
    final resolver = DohResolver(preset);
    final watch = Stopwatch()..start();
    try {
      final result = await resolver.lookup('example.com');
      return result.isEmpty ? null : watch.elapsed;
    } finally {
      resolver.close();
    }
  }
}

class _DnsHttpOverrides extends HttpOverrides {
  _DnsHttpOverrides(this._dns);

  final DnsService _dns;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = (uri, proxyHost, proxyPort) =>
        _connect(uri, proxyHost, proxyPort, context);
    return client;
  }

  Future<ConnectionTask<Socket>> _connect(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
    SecurityContext? context,
  ) async {
    final host = proxyHost ?? uri.host;
    final port = proxyPort ?? uri.port;
    // Through a proxy the client builds the TLS tunnel itself.
    final secure = proxyHost == null && uri.isScheme('https');
    final addresses = await _dns.lookup(host);
    if (addresses.isEmpty) {
      return secure
          ? SecureSocket.startConnect(host, port, context: context)
          : Socket.startConnect(host, port);
    }
    return DohResolver.connectAddresses(
      addresses,
      port,
      tlsHost: secure ? host : null,
      context: context,
    );
  }
}
