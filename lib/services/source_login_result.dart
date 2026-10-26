import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Outcome of one source check, before anything is stored on the device.
enum SourceLoginKind {
  ok,
  invalidAddress,
  unreachable,
  wrongService,
  badCredentials,
  expired,
  disabled,
  banned,
  serverError,
}

class SourceLoginResult {
  const SourceLoginResult(this.kind);
  final SourceLoginKind kind;
  bool get ok => kind == SourceLoginKind.ok;

  String get message => switch (kind) {
    SourceLoginKind.ok => '',
    SourceLoginKind.invalidAddress =>
      'Inserisci un indirizzo http o https valido.',
    SourceLoginKind.unreachable => 'Impossibile raggiungere il server. Controlla l’indirizzo e la connessione.',
    SourceLoginKind.wrongService =>
      'L’indirizzo non corrisponde al servizio. Controlla l’URL.',
    SourceLoginKind.badCredentials => 'Nome utente o password non corretti.',
    SourceLoginKind.expired => 'L’account della sorgente è scaduto.',
    SourceLoginKind.disabled => 'L’account della sorgente è disattivato.',
    SourceLoginKind.banned => 'L’account della sorgente è bloccato.',
    SourceLoginKind.serverError =>
      'Il server ha risposto con un errore. Controlla l’indirizzo e riprova.',
  };
}

/// Rejects a missing scheme or host before any network attempt.
SourceLoginResult? invalidSourceAddress(String server) {
  final uri = Uri.tryParse(server.trim());
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty) {
    return const SourceLoginResult(SourceLoginKind.invalidAddress);
  }
  return null;
}

bool _networkError(Object error) =>
    error is TimeoutException ||
    error is SocketException ||
    error is HandshakeException ||
    error is TlsException ||
    error is HttpException ||
    error is http.ClientException;

/// Maps a transport failure or an HTTP body to a message the user can act on.
SourceLoginResult classifySourceLogin({
  Object? error,
  int? statusCode,
  Object? body,
}) {
  if (error != null) {
    if (error is FormatException) {
      return const SourceLoginResult(SourceLoginKind.wrongService);
    }
    if (_networkError(error)) {
      return const SourceLoginResult(SourceLoginKind.unreachable);
    }
    return const SourceLoginResult(SourceLoginKind.serverError);
  }
  final code = statusCode ?? 0;
  if (code == 404) {
    return const SourceLoginResult(SourceLoginKind.wrongService);
  }
  if (code == 401 || code == 403) {
    return const SourceLoginResult(SourceLoginKind.badCredentials);
  }
  if (code != 200) {
    return const SourceLoginResult(SourceLoginKind.serverError);
  }
  if (body is! Map) {
    return const SourceLoginResult(SourceLoginKind.wrongService);
  }
  final info = body['user_info'];
  if (info is! Map) {
    return const SourceLoginResult(SourceLoginKind.wrongService);
  }
  final auth = info['auth'];
  if (auth == 1 || auth == '1') {
    return const SourceLoginResult(SourceLoginKind.ok);
  }
  final status = info['status']?.toString().toLowerCase() ?? '';
  if (status.contains('expir')) {
    return const SourceLoginResult(SourceLoginKind.expired);
  }
  if (status.contains('ban')) {
    return const SourceLoginResult(SourceLoginKind.banned);
  }
  if (status.contains('disable')) {
    return const SourceLoginResult(SourceLoginKind.disabled);
  }
  return const SourceLoginResult(SourceLoginKind.badCredentials);
}
