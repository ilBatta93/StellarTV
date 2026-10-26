import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/source_login_result.dart';

void main() {
  test('timeout and DNS mean the server cannot be reached', () {
    const message =
        'Impossibile raggiungere il server. Controlla l’indirizzo e la connessione.';
    expect(
      classifySourceLogin(error: TimeoutException('slow')).message,
      message,
    );
    expect(
      classifySourceLogin(error: const SocketException('Failed host lookup'))
          .kind,
      SourceLoginKind.unreachable,
    );
    expect(
      classifySourceLogin(error: const SocketException('Connection refused'))
          .message,
      message,
    );
  });

  test('HTTP 404 or an unexpected body means the address is wrong', () {
    const message = 'L’indirizzo non corrisponde al servizio. Controlla l’URL.';
    expect(classifySourceLogin(statusCode: 404).message, message);
    expect(
      classifySourceLogin(statusCode: 200, body: 'not-json').message,
      message,
    );
    expect(
      classifySourceLogin(error: const FormatException('bad')).kind,
      SourceLoginKind.wrongService,
    );
  });

  test('a refused sign-in means the username or password is wrong', () {
    const message = 'Nome utente o password non corretti.';
    expect(
      classifySourceLogin(
        statusCode: 200,
        body: {
          'user_info': {'auth': 0},
        },
      ).message,
      message,
    );
    expect(classifySourceLogin(statusCode: 401).message, message);
    expect(
      classifySourceLogin(statusCode: 403).kind,
      SourceLoginKind.badCredentials,
    );
  });

  test('an explicit account status is not reported as a bad password', () {
    expect(
      classifySourceLogin(
        statusCode: 200,
        body: {
          'user_info': {'auth': 0, 'status': 'Expired'},
        },
      ).kind,
      SourceLoginKind.expired,
    );
    expect(
      classifySourceLogin(
        statusCode: 200,
        body: {
          'user_info': {'auth': 1},
        },
      ).ok,
      isTrue,
    );
  });

  test('a missing scheme is rejected before the network', () {
    expect(
      invalidSourceAddress('tuo-server.com:8080')?.kind,
      SourceLoginKind.invalidAddress,
    );
    expect(invalidSourceAddress('http://ok.example'), isNull);
  });
}
