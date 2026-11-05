import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../models/dns_resolver_policy.dart';
import 'doh_resolver.dart';

/// Local HTTP proxy that lets mpv reach plain-http streams through the app
/// DNS: mpv has no resolver hook, but honours `http-proxy`. It runs in its own
/// isolate so piping video bytes never competes with the UI thread.
///
/// One request per connection (`Connection: close`), so every redirect or
/// segment on another host is resolved again. Nothing is logged.
class DnsStreamProxy {
  DnsStreamProxy._(this._isolate, this.port);

  final Isolate _isolate;
  final int port;

  String get url => 'http://127.0.0.1:$port';

  static Future<DnsStreamProxy> start(DnsResolverPreset preset) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(
      _main,
      _ProxyConfig(ready.sendPort, preset),
      debugName: 'dns-stream-proxy',
    );
    final port = await ready.first.timeout(const Duration(seconds: 5));
    ready.close();
    if (port is! int) {
      isolate.kill(priority: Isolate.immediate);
      throw StateError('Proxy DNS non avviato');
    }
    return DnsStreamProxy._(isolate, port);
  }

  void stop() => _isolate.kill(priority: Isolate.immediate);
}

class _ProxyConfig {
  final SendPort ready;
  final DnsResolverPreset preset;

  _ProxyConfig(this.ready, this.preset);
}

Future<void> _main(_ProxyConfig config) async {
  final resolver = DohResolver(config.preset);
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  config.ready.send(server.port);
  await for (final client in server) {
    unawaited(_serve(client, resolver));
  }
}

const _maxHead = 32 * 1024;

Future<void> _serve(Socket client, DohResolver resolver) async {
  final head = BytesBuilder(copy: false);
  final headDone = Completer<Uint8List>();
  Socket? upstream;
  final pending = <List<int>>[];
  late final StreamSubscription<Uint8List> sub;

  void fail() {
    client.destroy();
    upstream?.destroy();
  }

  sub = client.listen(
    (data) {
      final up = upstream;
      if (up != null) {
        up.add(data);
        return;
      }
      if (headDone.isCompleted) {
        pending.add(data);
        return;
      }
      head.add(data);
      final bytes = head.toBytes();
      final end = _headerEnd(bytes);
      if (end >= 0) {
        headDone.complete(bytes);
      } else if (bytes.length > _maxHead) {
        sub.cancel();
        fail();
      }
    },
    onError: (_) => fail(),
    onDone: () {
      if (!headDone.isCompleted) {
        fail();
      } else {
        upstream?.close().catchError((_) => null);
      }
    },
    cancelOnError: true,
  );

  final Uint8List raw;
  try {
    raw = await headDone.future.timeout(const Duration(seconds: 20));
  } catch (_) {
    await sub.cancel();
    fail();
    return;
  }
  final end = _headerEnd(raw);
  final headText = latin1.decode(raw.sublist(0, end));
  final rest = raw.sublist(end + 4);
  final lines = headText.split('\r\n');
  final requestLine = lines.first.split(' ');
  if (requestLine.length < 3) {
    await _reply(client, '400 Bad Request');
    return;
  }
  final method = requestLine[0];
  final target = requestLine[1];
  final version = requestLine[2];

  final String host;
  final int port;
  final bool tunnel = method.toUpperCase() == 'CONNECT';
  String? forwardHead;
  if (tunnel) {
    final colon = target.lastIndexOf(':');
    if (colon <= 0) {
      await _reply(client, '400 Bad Request');
      return;
    }
    host = target.substring(0, colon).replaceAll(RegExp(r'^\[|\]$'), '');
    port = int.tryParse(target.substring(colon + 1)) ?? 443;
  } else {
    final uri = Uri.tryParse(target);
    if (uri == null || uri.scheme != 'http' || uri.host.isEmpty) {
      await _reply(client, '400 Bad Request');
      return;
    }
    host = uri.host;
    port = uri.hasPort ? uri.port : 80;
    final path = uri.hasQuery
        ? '${uri.path.isEmpty ? '/' : uri.path}?${uri.query}'
        : (uri.path.isEmpty ? '/' : uri.path);
    final headers = <String>[];
    var hasHost = false;
    for (final line in lines.skip(1)) {
      final name = line.split(':').first.trim().toLowerCase();
      if (name == 'proxy-connection' ||
          name == 'connection' ||
          name == 'keep-alive' ||
          name == 'proxy-authorization') {
        continue;
      }
      if (name == 'host') hasHost = true;
      headers.add(line);
    }
    if (!hasHost) headers.add('Host: ${uri.authority}');
    headers.add('Connection: close');
    forwardHead = '$method $path $version\r\n${headers.join('\r\n')}\r\n\r\n';
  }

  try {
    final addresses = await resolver.lookup(host);
    final task = addresses.isEmpty
        ? await Socket.startConnect(host, port)
        : await DohResolver.connectAddresses(addresses, port);
    final socket = await task.socket.timeout(const Duration(seconds: 12));
    socket.setOption(SocketOption.tcpNoDelay, true);
    if (tunnel) {
      client.add(latin1.encode('HTTP/1.1 200 Connection established\r\n\r\n'));
    } else {
      socket.add(latin1.encode(forwardHead!));
    }
    if (rest.isNotEmpty) socket.add(rest);
    for (final chunk in pending) {
      socket.add(chunk);
    }
    pending.clear();
    upstream = socket;
  } catch (_) {
    await sub.cancel();
    await _reply(client, '502 Bad Gateway');
    return;
  }

  try {
    await client.addStream(upstream);
    await client.close();
  } catch (_) {
    fail();
  } finally {
    await sub.cancel();
    upstream.destroy();
  }
}

int _headerEnd(Uint8List bytes) {
  for (var i = 0; i + 3 < bytes.length; i++) {
    if (bytes[i] == 13 &&
        bytes[i + 1] == 10 &&
        bytes[i + 2] == 13 &&
        bytes[i + 3] == 10) {
      return i;
    }
  }
  return -1;
}

Future<void> _reply(Socket client, String status) async {
  try {
    client.add(
      latin1.encode(
        'HTTP/1.1 $status\r\nConnection: close\r\nContent-Length: 0\r\n\r\n',
      ),
    );
    await client.close();
  } catch (_) {
    client.destroy();
  }
}
