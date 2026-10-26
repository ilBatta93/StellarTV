import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../models/channel.dart';
import 'image_url.dart';
import '../models/content_type.dart';

/// Live download progress of one playlist section.
class CatalogProgress {
  final int bytes;
  final int items;
  const CatalogProgress({this.bytes = 0, this.items = 0});

  String get label {
    final parts = <String>[];
    if (bytes > 0) parts.add(formatBytes(bytes));
    if (items > 0) parts.add('${formatCount(items)} titoli');
    return parts.join(' · ');
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
  }

  static String formatCount(int n) {
    final s = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write('.');
      out.write(s[i]);
    }
    return out.toString();
  }
}

class XtreamDownloadException implements Exception {
  final String message;
  const XtreamDownloadException(this.message);
  @override
  String toString() => message;
}

/// Downloads one Xtream section (live / movie / series) in a background
/// isolate. The JSON list is parsed while it streams in, element by element,
/// so huge playlists never sit in memory as one giant string and the UI
/// thread never decodes them. A short truncated response keeps every complete
/// element. A truncated or failed list of 500 titles or more is an error, so
/// the section stays retryable instead of being marked ready.
Future<List<Channel>> downloadXtreamSection({
  required String base,
  required String username,
  required String password,
  required ContentType type,
  void Function(CatalogProgress progress)? onProgress,
  Duration maxDuration = const Duration(minutes: 15),
}) async {
  final port = ReceivePort();
  final exitPort = ReceivePort();
  final errorPort = ReceivePort();
  final completer = Completer<List<Channel>>();
  Isolate? isolate;
  Timer? watchdog;

  void finish({List<Channel>? value, Object? error}) {
    if (completer.isCompleted) return;
    if (error != null) {
      completer.completeError(error);
    } else {
      completer.complete(value ?? const []);
    }
  }

  port.listen((message) {
    if (message is _Progress) {
      onProgress?.call(
        CatalogProgress(bytes: message.bytes, items: message.items),
      );
    } else if (message is _Done) {
      finish(value: message.channels);
    } else if (message is _Failure) {
      finish(error: XtreamDownloadException(message.message));
    }
  });
  errorPort.listen((message) {
    final text = message is List && message.isNotEmpty
        ? message.first
        : message;
    finish(
      error: XtreamDownloadException(
        'Errore interno durante il caricamento ($text)',
      ),
    );
  });
  exitPort.listen((_) {
    // Give the final message a moment to arrive before declaring failure.
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      finish(
        error: const XtreamDownloadException(
          'Caricamento interrotto. Riprova.',
        ),
      );
    });
  });

  try {
    isolate = await Isolate.spawn(
      _isolateEntry,
      _Job(port.sendPort, base, username, password, type),
      onExit: exitPort.sendPort,
      onError: errorPort.sendPort,
      errorsAreFatal: true,
      debugName: 'xtream-${type.name}',
    );
    watchdog = Timer(maxDuration, () {
      finish(
        error: const XtreamDownloadException(
          'Il server impiega troppo tempo a inviare la lista. Riprova più tardi.',
        ),
      );
    });
    return await completer.future;
  } finally {
    watchdog?.cancel();
    isolate?.kill(priority: Isolate.immediate);
    port.close();
    exitPort.close();
    errorPort.close();
  }
}

// ---------------------------------------------------------------------------
// Background isolate
// ---------------------------------------------------------------------------

class _Job {
  final SendPort port;
  final String base;
  final String username;
  final String password;
  final ContentType type;
  const _Job(this.port, this.base, this.username, this.password, this.type);
}

class _Progress {
  final int bytes;
  final int items;
  const _Progress(this.bytes, this.items);
}

class _Done {
  final List<Channel> channels;
  const _Done(this.channels);
}

class _Failure {
  final String message;
  const _Failure(this.message);
}

const _userAgents = [
  'okhttp/4.12.0',
  'VLC/3.0.20 LibVLC/3.0.20',
  'IPTVSmartersPro',
];

Future<void> _isolateEntry(_Job job) async {
  try {
    final channels = await _runJob(job);
    // Transfers the list without copying it.
    Isolate.exit(job.port, _Done(channels));
  } catch (e) {
    job.port.send(_Failure(_friendlyError(e)));
  }
}

String _action(ContentType type) => switch (type) {
  ContentType.live => 'get_live_streams',
  ContentType.movie => 'get_vod_streams',
  _ => 'get_series',
};

String _categoryAction(ContentType type) => switch (type) {
  ContentType.live => 'get_live_categories',
  ContentType.movie => 'get_vod_categories',
  _ => 'get_series_categories',
};

String _apiUrl(_Job job, String action) =>
    '${job.base}/player_api.php?username=${Uri.encodeComponent(job.username)}'
    '&password=${Uri.encodeComponent(job.password)}&action=$action';

Future<List<Channel>> _runJob(_Job job) async {
  final categories = await _fetchCategories(job);
  final mapper = _ChannelMapper(job, categories);

  List<Channel> best = const [];
  Object? lastError;
  for (var attempt = 0; attempt < _userAgents.length; attempt++) {
    final items = <Channel>[];
    try {
      final complete = await _streamList(
        url: _apiUrl(job, _action(job.type)),
        attempt: attempt,
        onElement: (map) {
          final channel = mapper.map(map);
          if (channel != null) items.add(channel);
          return items.length;
        },
        port: job.port,
      );
      if (complete) return items;
      lastError = const _Truncated();
    } on _Fatal {
      rethrow;
    } catch (e) {
      lastError = e;
    }
    if (items.length > best.length) best = items;
    if (attempt < _userAgents.length - 1) {
      await Future<void>.delayed(Duration(seconds: 2 + attempt * 3));
    }
  }
  // A large incomplete list must stay retryable. Publishing it would mark
  // the section ready and hide every title that never arrived.
  if (best.isNotEmpty && best.length < 500) return best;
  throw lastError ?? const _Truncated();
}

Future<Map<String, String>> _fetchCategories(_Job job) async {
  for (var attempt = 0; attempt < 2; attempt++) {
    final map = <String, String>{};
    try {
      await _streamList(
        url: _apiUrl(job, _categoryAction(job.type)),
        attempt: attempt,
        onElement: (item) {
          map[item['category_id']?.toString() ?? ''] =
              item['category_name']?.toString() ?? 'Senza categoria';
          return 0;
        },
      );
      return map;
    } catch (_) {
      if (map.isNotEmpty) return map;
    }
  }
  return const {};
}

/// Streams a JSON array and calls [onElement] for every complete object.
/// Returns true when the closing bracket was received.
Future<bool> _streamList({
  required String url,
  required int attempt,
  required int Function(Map<String, dynamic> item) onElement,
  SendPort? port,
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 15)
    ..userAgent = _userAgents[attempt % _userAgents.length];
  try {
    final request = await client
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 30));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json, */*');
    if (attempt > 0) {
      // Some proxies cut compressed streams: ask for plain bytes on retries.
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    }
    // Big panels build the list before sending the first byte.
    final response = await request.close().timeout(
      const Duration(seconds: 150),
    );
    final status = response.statusCode;
    if (status != 200) {
      await response.drain<void>().catchError((_) {});
      if (status == 401 || status == 403) {
        throw _Fatal(
          'Il server ha rifiutato l\'accesso (HTTP $status). '
          'Controlla che l\'abbonamento sia attivo.',
        );
      }
      throw HttpException('HTTP $status');
    }

    final parser = _JsonArrayStreamer(onElement);
    var bytes = 0;
    var lastReport = DateTime.now();
    await for (final chunk in response.timeout(const Duration(seconds: 60))) {
      bytes += chunk.length;
      parser.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
      if (port != null) {
        final now = DateTime.now();
        if (now.difference(lastReport).inMilliseconds >= 400) {
          lastReport = now;
          port.send(_Progress(bytes, parser.count));
        }
      }
      if (parser.isComplete) break;
    }
    port?.send(_Progress(bytes, parser.count));
    return parser.finish();
  } finally {
    client.close(force: true);
  }
}

class _Truncated implements Exception {
  const _Truncated();
}

class _Fatal implements Exception {
  final String message;
  const _Fatal(this.message);
}

String _friendlyError(Object e) {
  if (e is _Fatal) return e.message;
  if (e is _Truncated) {
    return 'Il server ha interrotto l\'invio della lista. Riprova tra poco.';
  }
  if (e is _BadResponse) return e.message;
  if (e is TimeoutException) {
    return 'Il server della playlist non risponde (tempo scaduto). Riprova.';
  }
  if (e is SocketException) {
    return 'Impossibile raggiungere il server della playlist. '
        'Controlla la connessione e riprova.';
  }
  if (e is HttpException) {
    return 'Il server della playlist ha risposto con un errore (${e.message}).';
  }
  if (e is HandshakeException) {
    return 'Connessione sicura non riuscita con il server della playlist.';
  }
  return 'Caricamento non riuscito ($e)';
}

class _BadResponse implements Exception {
  final String message;
  const _BadResponse(this.message);
}

/// Incremental scanner for `[ {...}, {...} ]` payloads. Some panels answer
/// with an object keyed by id instead of a list: that shape is buffered and
/// decoded at the end.
class _JsonArrayStreamer {
  final int Function(Map<String, dynamic> item) onElement;
  _JsonArrayStreamer(this.onElement);

  int count = 0;
  bool isComplete = false;
  bool _started = false;
  bool _objectMode = false;
  final BytesBuilder _objectBuffer = BytesBuilder(copy: false);
  final BytesBuilder _element = BytesBuilder(copy: false);
  final List<int> _preview = [];
  int _depth = 0;
  bool _inString = false;
  bool _escape = false;
  bool _capturing = false;

  void add(Uint8List chunk) {
    if (isComplete) return;
    var i = 0;
    if (!_started) {
      for (; i < chunk.length; i++) {
        final b = chunk[i];
        if (b == 0x5B) {
          _started = true;
          _depth = 1;
          i++;
          break;
        }
        if (b == 0x7B) {
          _started = true;
          _objectMode = true;
          break;
        }
        if (_preview.length < 80) _preview.add(b);
      }
      if (!_started) return;
    }
    if (_objectMode) {
      _objectBuffer.add(i == 0 ? chunk : Uint8List.sublistView(chunk, i));
      return;
    }

    var elementStart = _capturing ? i : -1;
    for (; i < chunk.length; i++) {
      final b = chunk[i];
      if (_inString) {
        if (_escape) {
          _escape = false;
        } else if (b == 0x5C) {
          _escape = true;
        } else if (b == 0x22) {
          _inString = false;
        }
        continue;
      }
      switch (b) {
        case 0x22:
          _inString = true;
        case 0x7B || 0x5B:
          if (_depth == 1) {
            _capturing = b == 0x7B;
            elementStart = _capturing ? i : -1;
          }
          _depth++;
        case 0x7D || 0x5D:
          _depth--;
          if (_depth == 1 && b == 0x7D && elementStart >= 0) {
            _emit(chunk, elementStart, i + 1);
            elementStart = -1;
            _capturing = false;
          } else if (_depth == 0) {
            isComplete = true;
            return;
          }
      }
    }
    if (_capturing && elementStart >= 0) {
      _element.add(Uint8List.sublistView(chunk, elementStart));
    }
  }

  void _emit(Uint8List chunk, int start, int end) {
    Uint8List bytes;
    if (_element.isEmpty) {
      bytes = Uint8List.sublistView(chunk, start, end);
    } else {
      _element.add(Uint8List.sublistView(chunk, start, end));
      bytes = _element.takeBytes();
    }
    try {
      final value = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      if (value is Map) {
        count = onElement(value.cast<String, dynamic>());
      }
    } catch (_) {
      // Skip a single malformed element instead of losing the whole list.
    }
  }

  /// Returns true when the payload was received completely.
  bool finish() {
    if (_objectMode) {
      final text = utf8.decode(_objectBuffer.takeBytes(), allowMalformed: true);
      dynamic value;
      try {
        value = jsonDecode(text);
      } on FormatException {
        throw const _Truncated();
      }
      if (value is Map) {
        final info = value['user_info'];
        if (info is Map && '${info['auth']}' == '0') {
          throw const _Fatal('Credenziali non valide o abbonamento scaduto.');
        }
        for (final v in value.values) {
          if (v is Map) count = onElement(v.cast<String, dynamic>());
        }
      }
      return true;
    }
    if (!_started) {
      final preview = utf8
          .decode(_preview, allowMalformed: true)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (preview.isEmpty) {
        // Empty body: some panels answer this way when a section is empty.
        return true;
      }
      throw _BadResponse('Risposta non valida dal server: "$preview"');
    }
    return isComplete;
  }
}

/// Maps raw Xtream objects to [Channel]s (runs inside the isolate).
class _ChannelMapper {
  final _Job job;
  final Map<String, String> categories;
  late final String _user = Uri.encodeComponent(job.username);
  late final String _pass = Uri.encodeComponent(job.password);
  _ChannelMapper(this.job, this.categories);

  String _group(Map<String, dynamic> item) =>
      categories[item['category_id']?.toString() ?? ''] ?? 'Senza categoria';

  Channel? map(Map<String, dynamic> item) {
    final base = job.base;
    switch (job.type) {
      case ContentType.live:
        final id = item['stream_id'];
        if (id == null) return null;
        return Channel(
          id: 'live_$id',
          name: item['name']?.toString() ?? 'Sconosciuto',
          url: '$base/live/$_user/$_pass/$id.m3u8',
          logo: cleanImageUrl(item['stream_icon']),
          group: _group(item),
          type: ContentType.live,
          tvgId: item['epg_channel_id']?.toString(),
          archiveDays: item['tv_archive']?.toString() == '1'
              ? (int.tryParse(item['tv_archive_duration']?.toString() ?? '') ??
                        0)
                    .clamp(0, 365)
              : 0,
        );
      case ContentType.movie:
        final id = item['stream_id'];
        if (id == null) return null;
        return Channel(
          id: 'movie_$id',
          name: item['name']?.toString() ?? 'Sconosciuto',
          url:
              '$base/movie/$_user/$_pass/$id.${item['container_extension'] ?? 'mp4'}',
          logo: firstImageUrl([
            item['stream_icon'],
            item['cover_big'],
            item['movie_image'],
            item['cover'],
            item['poster_path'],
          ]),
          group: _group(item),
          type: ContentType.movie,
          addedAt: int.tryParse(item['added']?.toString() ?? '') ?? 0,
          releaseDate: Channel.parseReleaseDate(
            item['releasedate'] ??
                item['releaseDate'] ??
                item['release_date'] ??
                item['year'],
          ),
        );
      default:
        final seriesId = item['series_id']?.toString() ?? '';
        if (seriesId.isEmpty) return null;
        return Channel(
          id: 'series_$seriesId',
          name: item['name']?.toString() ?? 'Sconosciuto',
          url: '',
          logo: firstImageUrl([
            item['cover'],
            item['cover_big'],
            item['stream_icon'],
            item['poster_path'],
          ]),
          group: _group(item),
          type: ContentType.series,
          seriesKey: 'series_$seriesId',
          seriesName: item['name']?.toString(),
          plot: item['plot']?.toString(),
          isSeriesFolder: true,
          addedAt:
              int.tryParse(
                (item['last_modified'] ?? item['added'])?.toString() ?? '',
              ) ??
              0,
          releaseDate: Channel.parseReleaseDate(
            item['releaseDate'] ??
                item['release_date'] ??
                item['releasedate'] ??
                item['year'],
          ),
        );
    }
  }
}
