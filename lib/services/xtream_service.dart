import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/series_details.dart';
import 'xtream_downloader.dart';

export 'xtream_downloader.dart' show CatalogProgress;

class XtreamService {
  static const _headers = {
    'Connection': 'close',
    'User-Agent': 'StellarTV/1.0',
  };

  /// Alcuni pannelli IPTV rifiutano o troncano le risposte per client
  /// sconosciuti: ai tentativi successivi ci presentiamo come player diffusi.
  static const _userAgents = [
    'StellarTV/1.0',
    'okhttp/4.12.0',
    'VLC/3.0.20 LibVLC/3.0.20',
    'IPTVSmartersPro',
  ];

  /// Scarica e decodifica una risposta JSON in modo robusto:
  /// - legge i dati a blocchi, con un limite di attesa tra un blocco e
  ///   l'altro (non un limite totale): le liste enormi su TV/emulatori lenti
  ///   non vengono piu interrotte a meta;
  /// - riprova fino a 4 volte cambiando compressione e User-Agent;
  /// - ignora testo spurio prima del JSON (BOM, avvisi PHP) e, se la lista
  ///   arriva comunque troncata, recupera tutti gli elementi completi;
  /// - decodifica in un isolate separato, cosi l'interfaccia non si blocca.
  Future<dynamic> _getJson(String url, {bool throwOnHttpError = false}) async {
    Object? lastError;
    String? diagnostic;
    dynamic bestPartial;
    var bestPartialCount = -1;

    for (var attempt = 0; attempt < _userAgents.length; attempt++) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 20)
        ..idleTimeout = const Duration(seconds: 10)
        ..userAgent = _userAgents[attempt];
      try {
        final request = await client
            .getUrl(Uri.parse(url))
            .timeout(const Duration(seconds: 25));
        request.headers.set(HttpHeaders.acceptHeader, 'application/json, */*');
        request.headers.set(HttpHeaders.connectionHeader, 'close');
        if (attempt > 0) {
          // Con alcuni server/proxy la risposta compressa si interrompe:
          // dal secondo tentativo la chiediamo non compressa.
          request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        }
        final response = await request.close().timeout(
          const Duration(seconds: 60),
        );
        if (response.statusCode != 200) {
          await response.drain<void>().catchError((_) {});
          if (throwOnHttpError) {
            throw HttpException(
              'Impossibile caricare i dati (HTTP ${response.statusCode})',
            );
          }
          return null;
        }

        final builder = BytesBuilder(copy: false);
        var truncated = false;
        try {
          await for (final chunk in response.timeout(
            const Duration(seconds: 45),
          )) {
            builder.add(chunk);
          }
        } catch (e) {
          truncated = true;
          lastError = e;
        }
        final bytes = builder.takeBytes();
        final expected = response.contentLength;
        if (expected > 0 && bytes.length < expected) truncated = true;

        final result = await Isolate.run(() => _decodeLenient(bytes));
        if (result.value != null && !truncated && !result.salvaged) {
          return result.value;
        }
        if (result.value != null) {
          final count = result.value is List
              ? (result.value as List).length
              : 0;
          if (count > bestPartialCount) {
            bestPartial = result.value;
            bestPartialCount = count;
          }
        }
        diagnostic = truncated
            ? 'ricevuti ${bytes.length ~/ 1024} KB'
                  '${expected > 0 ? ' su ${expected ~/ 1024} KB' : ''}'
            : result.diagnostic;
        lastError = const FormatException('Risposta incompleta dal server');
      } on HttpException catch (e) {
        if (throwOnHttpError) {
          throw Exception(e.message);
        }
        lastError = e;
      } catch (e) {
        lastError = e;
      } finally {
        client.close(force: true);
      }
      if (attempt < _userAgents.length - 1) {
        await Future.delayed(Duration(seconds: 1 + attempt * 2));
      }
    }

    // Meglio una lista quasi completa che nessuna lista.
    if (bestPartial != null) return bestPartial;

    if (lastError is FormatException) {
      throw Exception(
        'Il server ha inviato una lista incompleta. Riprova tra poco.'
        '${diagnostic != null ? ' ($diagnostic)' : ''}',
      );
    }
    if (lastError is TimeoutException) {
      throw Exception(
        'Il server della playlist non risponde. Controlla la connessione e riprova.',
      );
    }
    if (lastError is SocketException || lastError is HttpException) {
      throw Exception(
        'Impossibile raggiungere il server della playlist. Controlla la connessione e riprova.',
      );
    }
    throw lastError ?? Exception('Errore di rete');
  }

  String _normalizeServerUrl(String server) {
    var url = server.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return url;
  }

  String _buildApiUrl(String server, String username, String password) {
    final base = _normalizeServerUrl(server);
    return '$base/player_api.php?username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}';
  }

  /// Raw account details from the provider (`user_info` + `server_info` of
  /// player_api.php): expiry, connections, status, server time zone...
  Future<Map<String, dynamic>> accountInfo({
    required String server,
    required String username,
    required String password,
  }) async {
    final apiUrl = _buildApiUrl(server, username, password);
    final response = await http
        .get(Uri.parse(apiUrl), headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception(
        'Il provider ha risposto con errore ${response.statusCode}.',
      );
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> || data['user_info'] is! Map) {
      throw Exception('Il provider non fornisce informazioni sull\'account.');
    }
    return data;
  }

  Future<bool> authenticate({
    required String server,
    required String username,
    required String password,
  }) async {
    final apiUrl = _buildApiUrl(server, username, password);
    final response = await http.get(Uri.parse(apiUrl), headers: _headers);
    if (response.statusCode != 200) return false;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final userInfo = data['user_info'] as Map<String, dynamic>?;
    if (userInfo == null) return false;
    final status = userInfo['auth'] ?? 0;
    return status == 1;
  }

  Future<List<Channel>> _section(
    ContentType type,
    String server,
    String username,
    String password,
    void Function(CatalogProgress progress)? onProgress,
  ) => downloadXtreamSection(
    base: _normalizeServerUrl(server),
    username: username,
    password: password,
    type: type,
    onProgress: onProgress,
  );

  Future<List<Channel>> getLiveChannels({
    required String server,
    required String username,
    required String password,
    void Function(CatalogProgress progress)? onProgress,
  }) => _section(ContentType.live, server, username, password, onProgress);

  Future<List<Channel>> getVodChannels({
    required String server,
    required String username,
    required String password,
    void Function(CatalogProgress progress)? onProgress,
  }) => _section(ContentType.movie, server, username, password, onProgress);

  Future<List<Channel>> getSeriesChannels({
    required String server,
    required String username,
    required String password,
    void Function(CatalogProgress progress)? onProgress,
  }) => _section(ContentType.series, server, username, password, onProgress);

  Future<SeriesDetails> getSeriesInfo({
    required String server,
    required String username,
    required String password,
    required Channel series,
  }) async {
    final base = _normalizeServerUrl(server);
    final seriesId = (series.seriesKey ?? series.id).replaceFirst(
      'series_',
      '',
    );
    final url =
        '$base/player_api.php?username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}&action=get_series_info&series_id=${Uri.encodeComponent(seriesId)}';
    final decoded = await _getJson(url, throwOnHttpError: true);
    if (decoded is! Map) {
      throw Exception('Risposta serie non valida dal server');
    }
    final data = decoded.cast<String, dynamic>();
    final info = _asMap(data['info']);
    final overview = (info['plot'] ?? info['description'] ?? series.plot ?? '')
        .toString();
    final cover = cleanImageUrl(info['cover']).isNotEmpty
        ? cleanImageUrl(info['cover'])
        : cleanImageUrl(series.logo);
    // Landscape artwork fits 16:9 episode cards better than the 2:3 cover.
    final rawBackdrops = info['backdrop_path'];
    final backdrops = rawBackdrops is List ? rawBackdrops : [rawBackdrops];
    final user = Uri.encodeComponent(username);
    final pass = Uri.encodeComponent(password);

    final seasons = <int, List<SeriesEpisode>>{};
    for (final episodeJson in _extractEpisodeMaps(data['episodes'])) {
      final streamId = (episodeJson['id'] ?? episodeJson['episode_id'])
          ?.toString();
      if (streamId == null || streamId.isEmpty) continue;
      final episodeInfo = _asMap(episodeJson['info']);
      final season =
          _toInt(episodeJson['season']) ?? _toInt(episodeInfo['season']) ?? 1;
      final number =
          _toInt(episodeJson['episode_num']) ??
          _toInt(episodeJson['episode']) ??
          (seasons[season]?.length ?? 0) + 1;
      final ext = (episodeJson['container_extension'] ?? 'mp4').toString();
      final title =
          (episodeJson['title'] ?? episodeInfo['name'] ?? 'Episodio $number')
              .toString();
      final image = [
        episodeInfo['movie_image'],
        episodeInfo['cover_big'],
        episodeJson['cover'],
        ...backdrops,
        cover,
      ].map(cleanImageUrl).firstWhere((u) => u.isNotEmpty, orElse: () => '');
      final channel = Channel(
        id: 'episode_$streamId',
        name:
            '${series.name} · S${season.toString().padLeft(2, '0')}E${number.toString().padLeft(2, '0')} · $title',
        url: '$base/series/$user/$pass/$streamId.$ext',
        logo: image,
        group: series.group,
        type: series.type,
        seriesKey: series.seriesKey ?? series.id,
        seriesName: series.name,
        season: season,
        episode: number,
        plot: episodeInfo['plot']?.toString(),
      );
      (seasons[season] ??= []).add(
        SeriesEpisode(
          channel: channel,
          season: season,
          number: number,
          title: title,
          overview: episodeInfo['plot']?.toString(),
          image: image.isEmpty ? null : image,
          duration: _durationFrom(episodeInfo, episodeJson),
        ),
      );
    }

    if (seasons.isEmpty) {
      throw Exception('Nessun episodio trovato per questa serie');
    }

    final ordered = seasons.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final e in ordered) {
      e.value.sort((a, b) => a.number.compareTo(b.number));
    }

    return SeriesDetails(
      series: series.copyWith(
        logo: cover.isNotEmpty ? cover : series.logo,
        plot: overview,
      ),
      overview: overview,
      seasons: [
        for (final e in ordered)
          SeriesSeason(
            number: e.key,
            name: e.key <= 0 ? 'Speciali' : 'Stagione ${e.key}',
            episodes: e.value,
          ),
      ],
    );
  }

  Iterable<Map<String, dynamic>> _extractEpisodeMaps(dynamic raw) sync* {
    if (raw is Map) {
      final entries = raw.entries.toList()
        ..sort(
          (a, b) =>
              _toInt(a.key)?.compareTo(_toInt(b.key) ?? 0) ??
              a.key.toString().compareTo(b.key.toString()),
        );
      for (final entry in entries) {
        yield* _extractEpisodeMaps(entry.value);
      }
      return;
    }
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          yield item.map((k, v) => MapEntry(k.toString(), v));
        } else {
          yield* _extractEpisodeMaps(item);
        }
      }
    }
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return {};
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  Duration? _durationFrom(
    Map<String, dynamic> info,
    Map<String, dynamic> episode,
  ) {
    final secs = _toInt(
      info['duration_secs'] ?? info['duration_sec'] ?? episode['duration_secs'],
    );
    if (secs != null && secs > 0) return Duration(seconds: secs);
    final raw = (info['duration'] ?? episode['duration'])?.toString();
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':').map(int.tryParse).toList();
    if (parts.contains(null)) return null;
    if (parts.length == 3) {
      return Duration(hours: parts[0]!, minutes: parts[1]!, seconds: parts[2]!);
    }
    if (parts.length == 2) {
      return Duration(minutes: parts[0]!, seconds: parts[1]!);
    }
    return null;
  }
}

/// Risultato della decodifica tollerante di una risposta Xtream.
typedef _LenientJson = ({dynamic value, bool salvaged, String? diagnostic});

/// Decodifica JSON tollerante (eseguita in un isolate):
/// salta BOM/testo prima del JSON e, se una lista e troncata, la chiude
/// dopo l'ultimo elemento completo.
_LenientJson _decodeLenient(Uint8List bytes) {
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  final trimmed = text.trimLeft();
  if (trimmed.isEmpty) {
    return (value: null, salvaged: false, diagnostic: 'risposta vuota');
  }
  final firstArray = text.indexOf('[');
  final firstObject = text.indexOf('{');
  int start;
  if (firstArray < 0) {
    start = firstObject;
  } else if (firstObject < 0) {
    start = firstArray;
  } else {
    start = firstArray < firstObject ? firstArray : firstObject;
  }
  if (start < 0) {
    final preview = trimmed.length > 60 ? trimmed.substring(0, 60) : trimmed;
    return (
      value: null,
      salvaged: false,
      diagnostic: 'risposta non valida: "${preview.replaceAll('\n', ' ')}"',
    );
  }
  final body = start == 0 ? text : text.substring(start);
  try {
    return (value: jsonDecode(body), salvaged: false, diagnostic: null);
  } on FormatException {
    // continua sotto con il recupero
  }
  if (body.startsWith('[')) {
    var cut = body.length;
    for (var i = 0; i < 60; i++) {
      final idx = body.lastIndexOf('}', cut - 1);
      if (idx <= 0) break;
      try {
        final value = jsonDecode('${body.substring(0, idx + 1)}]');
        if (value is List && value.isNotEmpty) {
          return (
            value: value,
            salvaged: true,
            diagnostic: 'lista troncata, recuperati ${value.length} elementi',
          );
        }
      } on FormatException {
        // prova con la graffa precedente
      }
      cut = idx;
    }
  }
  return (
    value: null,
    salvaged: false,
    diagnostic: 'ricevuti ${bytes.length ~/ 1024} KB non leggibili',
  );
}

/// Normalizes provider artwork: drops empty/"null" values, completes bare
/// TMDB paths and protocol-relative URLs, and encodes spaces.
String cleanImageUrl(Object? raw) {
  if (raw == null) return '';
  var u = raw.toString().trim();
  if (u.isEmpty || u == 'null' || u == 'false' || u == '0') return '';
  if (u.startsWith('//')) u = 'https:$u';
  if (u.startsWith('/') && RegExp(r'^/[A-Za-z0-9]+\.(jpg|jpeg|png|webp)$', caseSensitive: false).hasMatch(u)) {
    u = 'https://image.tmdb.org/t/p/w780$u';
  }
  if (!u.startsWith('http://') && !u.startsWith('https://')) return '';
  try {
    return Uri.encodeFull(Uri.decodeFull(u));
  } catch (_) {
    return u.replaceAll(' ', '%20');
  }
}
