import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'settings_service.dart';
import 'foreground_policy.dart';

enum ProviderCondition {
  online,
  limit,
  inactive,
  unauthorized,
  unreachable,
  unknown,
  unsupported,
}

class ProviderDiagnosis {
  const ProviderDiagnosis(this.condition, this.message);
  final ProviderCondition condition;
  final String message;
}

ProviderDiagnosis classifyProvider(
  int status,
  Object? data, {
  bool playbackFailed = false,
}) {
  if (status == 401 || status == 403)
    return const ProviderDiagnosis(
      ProviderCondition.unauthorized,
      'Accesso rifiutato: verifica i dati di accesso.',
    );
  if (status >= 500)
    return const ProviderDiagnosis(
      ProviderCondition.unreachable,
      'Il server segnala un errore. Potrebbe essere temporaneo.',
    );
  if (status != 200 || data is! Map || data['user_info'] is! Map)
    return const ProviderDiagnosis(
      ProviderCondition.unknown,
      'Risposta non verificabile: impossibile stabilire la causa.',
    );
  final u = data['user_info'] as Map;
  final state = '${u['status'] ?? ''}'.toLowerCase();
  if (['expired', 'disabled', 'banned'].contains(state))
    return const ProviderDiagnosis(
      ProviderCondition.inactive,
      'Account non attivo: scaduto o disabilitato.',
    );
  if (u['auth'] == 0 || u['auth'] == '0')
    return const ProviderDiagnosis(
      ProviderCondition.unauthorized,
      'Accesso rifiutato: verifica i dati di accesso.',
    );
  int? count(Object? x) => int.tryParse('$x');
  final active = count(u['active_cons']);
  final max = count(u['max_connections']);
  if (active != null && active >= 0 && max != null && max > 0 && active >= max)
    return ProviderDiagnosis(
      ProviderCondition.limit,
      'Limite connessioni raggiunto ($active/$max). Può includere questa riproduzione o una connessione appena chiusa: non prova che sia un altro dispositivo.',
    );
  if (state != 'active')
    return const ProviderDiagnosis(
      ProviderCondition.unknown,
      'Il server risponde, ma lo stato dell’account non è verificabile.',
    );
  return ProviderDiagnosis(
    ProviderCondition.online,
    playbackFailed
        ? 'Server raggiungibile e account attivo. Il problema può riguardare il singolo flusso, il formato o la rete; la causa non è certa.'
        : 'Server raggiungibile e account attivo. La disponibilità di ogni riproduzione non è garantita.',
  );
}

/// Single small request, no retries, polling, persistence, stream probe or cloud.
class ProviderDiagnosisService {
  static bool _busy = false;
  static Future<ProviderDiagnosis> check({
    String? playbackUrl,
    bool playbackFailed = false,
  }) async {
    if (_busy)
      return const ProviderDiagnosis(
        ProviderCondition.unknown,
        'È già in corso una verifica. Riprova tra pochi secondi.',
      );
    _busy = true;
    try {
      return await _check(playbackUrl, playbackFailed);
    } finally {
      _busy = false;
    }
  }

  static Future<ProviderDiagnosis> _check(
    String? playbackUrl,
    bool failed,
  ) async {
    http.Client? client;
    try {
      if (!ForegroundPolicy.instance.active)
        return const ProviderDiagnosis(
          ProviderCondition.unknown,
          'Verifica sospesa: torna nell’app e riprova.',
        );
      final credentials = await SettingsService().getXtreamCredentials();
      if (credentials == null)
        return const ProviderDiagnosis(
          ProviderCondition.unsupported,
          'Questo accesso non espone informazioni sullo stato del servizio.',
        );
      var base = credentials['server'] ?? '';
      if (!base.contains('://')) base = 'http://$base';
      final server = Uri.tryParse(base);
      if (server == null ||
          !['http', 'https'].contains(server.scheme) ||
          server.host.isEmpty)
        return const ProviderDiagnosis(
          ProviderCondition.unsupported,
          'Configurazione non verificabile.',
        );
      if (playbackUrl != null) {
        final media = Uri.tryParse(playbackUrl);
        final parts = media?.pathSegments ?? const <String>[];
        // Never diagnose a different saved account, local file or public URL.
        final pathAccount =
            parts.length >= 4 &&
            ['live', 'movie', 'series'].contains(parts[parts.length - 4]) &&
            parts[parts.length - 3] == credentials['username'] &&
            parts[parts.length - 2] == credentials['password'];
        final queryAccount =
            media?.queryParameters['username'] == credentials['username'] &&
            media?.queryParameters['password'] == credentials['password'];
        final shortLive =
            parts.length == 3 &&
            parts[0] == credentials['username'] &&
            parts[1] == credentials['password'];
        if (media == null ||
            media.host != server.host ||
            media.port != server.port ||
            !(pathAccount || queryAccount || shortLive))
          return const ProviderDiagnosis(
            ProviderCondition.unsupported,
            'Questa riproduzione non è associabile all’account salvato.',
          );
      }
      final path =
          '${server.path.replaceAll(RegExp(r'/+$'), '')}/player_api.php';
      final uri = server.replace(
        path: path,
        queryParameters: {
          'username': credentials['username'] ?? '',
          'password': credentials['password'] ?? '',
        },
        fragment: '',
      );
      client = http.Client();
      final transport = client;
      return await (() async {
        final response = await transport.send(
          http.Request('GET', uri)
            ..followRedirects = false
            ..headers['Connection'] = 'close'
            ..headers['User-Agent'] = 'StellarTV/1.0',
        );
        if (response.statusCode != 200)
          return classifyProvider(
            response.statusCode,
            null,
            playbackFailed: failed,
          );
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > 65536)
            return const ProviderDiagnosis(
              ProviderCondition.unknown,
              'Risposta non verificabile.',
            );
          bytes.addAll(chunk);
        }
        return classifyProvider(
          response.statusCode,
          jsonDecode(utf8.decode(bytes)),
          playbackFailed: failed,
        );
      })().timeout(const Duration(seconds: 8));
    } on TimeoutException {
      return const ProviderDiagnosis(
        ProviderCondition.unreachable,
        'Server non raggiungibile entro 8 secondi. Può dipendere dalla rete, dal server o da un blocco: offline non confermato.',
      );
    } catch (_) {
      return const ProviderDiagnosis(
        ProviderCondition.unknown,
        'Verifica non riuscita. Controlla la rete; la causa non è certa.',
      );
    } finally {
      client?.close();
    }
  }
}
