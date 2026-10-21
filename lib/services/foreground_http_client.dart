import 'package:http/http.dart' as http;

import 'foreground_policy.dart';

/// Guards every cloud HTTP hop, including Auth and PostgREST. An already
/// dispatched request may finish; no queued request starts while hidden.
class ForegroundHttpClient extends http.BaseClient {
  ForegroundHttpClient({http.Client? inner, ForegroundPolicy? policy})
    : _inner = inner ?? http.Client(),
      _policy = policy ?? ForegroundPolicy.instance;
  final http.Client _inner;
  final ForegroundPolicy _policy;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!_policy.active) {
      throw http.ClientException(
        'Attività cloud sospesa: app non visibile',
        request.url,
      );
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
