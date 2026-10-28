import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:stellar_tv/services/foreground_http_client.dart';
import 'package:stellar_tv/services/foreground_policy.dart';

void check(bool result, String rule) {
  if (!result) throw StateError(rule);
  print('PASS: $rule');
}

Future<void> main() async {
  final policy = ForegroundPolicy();
  var calls = 0;
  final pending = Completer<http.Response>();
  final client = ForegroundHttpClient(
    policy: policy,
    inner: MockClient((request) {
      calls++;
      return calls == 1
          ? pending.future
          : Future.value(http.Response('ok', 200));
    }),
  );
  final first = client.get(
    Uri.parse('https://example.invalid/rest/v1/personal_vaults'),
  );
  await Future<void>.delayed(Duration.zero);
  policy.setResumed(false);
  pending.complete(http.Response('ok', 200));
  check(
    (await first).statusCode == 200,
    'already dispatched request can finish safely',
  );
  for (final path in [
    'rest/v1/rpc/save_personal_vault',
    'auth/v1/token',
    'storage/v1/object',
    'api/public/kids-check',
    'api/public/pair',
  ]) {
    var rejected = false;
    try {
      await client.get(Uri.parse('https://example.invalid/$path'));
    } on http.ClientException {
      rejected = true;
    }
    check(
      rejected && calls == 1,
      'hidden app sends zero new requests to $path',
    );
  }
  policy.setResumed(true);
  check(
    (await client.get(
              Uri.parse('https://example.invalid/rest/v1/personal_vaults'),
            )).statusCode ==
            200 &&
        calls == 2,
    'foreground restores the same transport without duplicate sends',
  );
  client.close();
}
