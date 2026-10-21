import 'dart:async';

import 'package:http/http.dart' as http;

import 'foreground_policy.dart';

/// Guards every cloud HTTP hop, including Auth and PostgREST. An already
/// dispatched request may finish; no queued request starts while hidden.
class ForegroundHttpClient extends http.BaseClient {
  ForegroundHttpClient({http.Client? inner, ForegroundPolicy? policy})
    : _inner = inner,
      _policy = policy ?? ForegroundPolicy.instance;
  final http.Client? _inner;
  // The default transport is resolved per zone, so a shared guard never pins
  // the first zone's client (http.runWithClient overrides stay honoured).
  static final Expando<http.Client> _zoneClients = Expando();
  http.Client get _client =>
      _inner ?? (_zoneClients[Zone.current] ??= http.Client());
  final ForegroundPolicy _policy;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!_policy.active) {
      throw http.ClientException(
        'Attività cloud sospesa: app non visibile',
        request.url,
      );
    }
    return _client.send(request);
  }

  @override
  void close() => _client.close();
}
