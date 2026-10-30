import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:xml/xml_events.dart';

import 'epg_archive.dart';
import 'epg_channel_match.dart';
import 'epg_timeline.dart';

export 'epg_archive.dart' show EpgGuideSnapshot;

/// Programmes kept from one guide. Past this point the guide stays partial
/// instead of failing the whole download.
const epgProgrammeCap = 200000;

class EpgRefreshDeferred implements Exception {}

/// Only enumerated messages may leave the worker: never URLs/body/errors.
class EpgDownloadException implements Exception {
  final String message;
  const EpgDownloadException(this.message);
  @override
  String toString() => message;
}

class EpgDownloadJob {
  final List<String> urls;
  final String stagedPath;
  final Duration deadline;
  EpgDownloadJob(
    this.urls,
    this.stagedPath, {
    this.deadline = const Duration(minutes: 8),
  });
  Isolate? _isolate;
  final _done = Completer<EpgGuideSnapshot>();
  bool _canceled = false;
  void cancel() {
    _canceled = true;
    _isolate?.kill(priority: Isolate.immediate);
    if (!_done.isCompleted) _done.completeError(EpgRefreshDeferred());
  }

  Future<EpgGuideSnapshot> run() async {
    final port = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    Timer? timer;
    Timer? exitTimer;
    void fail(Object error) {
      if (!_done.isCompleted) _done.completeError(error);
    }

    port.listen((value) {
      if (_done.isCompleted) return;
      if (value is Map) _done.complete(EpgGuideSnapshot.fromHeader(value));
      if (value is EpgDownloadException) fail(value);
    });
    errors.listen(
      (_) => fail(
        const EpgDownloadException('Errore durante la lettura della guida TV.'),
      ),
    );
    exits.listen((_) {
      exitTimer = Timer(
        const Duration(milliseconds: 100),
        () => fail(
          const EpgDownloadException(
            'Caricamento della guida interrotto. Riprova.',
          ),
        ),
      );
    });
    try {
      // Attach an error handler before spawn can race with cancellation.
      final result = _done.future;
      final spawn = Isolate.spawn(
        _downloadEntry,
        (port.sendPort, urls, stagedPath),
        onError: errors.sendPort,
        onExit: exits.sendPort,
        errorsAreFatal: true,
        debugName: 'epg-download',
      );
      unawaited(
        spawn.then(
          (isolate) {
            _isolate = isolate;
            if (_canceled || _done.isCompleted) {
              isolate.kill(priority: Isolate.immediate);
            }
          },
          onError: (Object _) => fail(
            const EpgDownloadException(
              'Impossibile avviare la lettura della guida.',
            ),
          ),
        ),
      );
      timer = Timer(
        deadline,
        () => fail(
          const EpgDownloadException(
            'Tempo massimo per la guida superato. Riprova più tardi.',
          ),
        ),
      );
      return await result;
    } finally {
      timer?.cancel();
      exitTimer?.cancel();
      _isolate?.kill(priority: Isolate.immediate);
      port.close();
      errors.close();
      exits.close();
    }
  }
}

Future<void> _downloadEntry((SendPort, List<String>, String) job) async {
  final part = '${job.$3}.part';
  try {
    final merged = <String, dynamic>{
      'p': <String, dynamic>{},
      'n': <String, dynamic>{},
      'd': false,
    };
    EpgDownloadException? lastError;
    var read = 0;
    for (final url in job.$2) {
      try {
        final parsed = await _readSource(url)
            .timeout(const Duration(minutes: 6));
        if (parsed['d'] == true) merged['d'] = true;
        for (final key in ['p', 'n']) {
          final source = parsed[key];
          if (source is! Map) continue;
          source.forEach(
            (k, v) => (merged[key] as Map<String, dynamic>).putIfAbsent(
              k.toString(),
              () => v,
            ),
          );
        }
        read++;
      } catch (error) {
        lastError = friendlyEpgError(error);
      }
    }
    if (read == 0) {
      throw lastError ??
          const EpgDownloadException('Nessuna guida configurata.');
    }
    merged['t'] = DateTime.now().toIso8601String();
    final header = writeEpgArchive(job.$3, merged);
    Isolate.exit(job.$1, header);
  } catch (error) {
    try {
      final leftover = Directory(part);
      if (leftover.existsSync()) leftover.deleteSync(recursive: true);
    } catch (_) {}
    Isolate.exit(job.$1, friendlyEpgError(error));
  }
}

EpgDownloadException friendlyEpgError(Object error) {
  if (error is EpgDownloadException) return error;
  if (error is TimeoutException) {
    return const EpgDownloadException('Tempo di attesa della guida superato.');
  }
  if (error is HandshakeException) {
    return const EpgDownloadException(
      'Connessione sicura alla guida non riuscita.',
    );
  }
  if (error is SocketException) {
    return const EpgDownloadException(
      'Connessione alla guida non riuscita. Controlla la rete.',
    );
  }
  return const EpgDownloadException(
    'La risposta non contiene una guida TV valida.',
  );
}

Future<Map<String, dynamic>> _readSource(String url) async {
  const agents = ['StellarTV/1.0', 'IPTVSmartersPro', 'okhttp/4.12.0'];
  for (var attempt = 0; attempt < agents.length; attempt++) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const EpgDownloadException('Indirizzo della guida non valido.');
    }
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = const Duration(seconds: 20)
      ..userAgent = agents[attempt];
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 25));
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/xml, text/xml, */*',
      );
      request.headers.set(
        HttpHeaders.acceptEncodingHeader,
        attempt == 0 ? 'gzip' : 'identity',
      );
      request.headers.set(HttpHeaders.connectionHeader, 'close');
      final response = await request.close().timeout(
        const Duration(seconds: 45),
      );
      final status = response.statusCode;
      // Bounded compatibility fallback only for client-format refusals.
      if ((status == 403 || status == 406) && attempt < agents.length - 1) {
        // Cancel without retaining an arbitrary server error body.
        await response.listen((_) {}).cancel();
        continue;
      }
      if (status != 200) {
        throw EpgDownloadException('Guida non disponibile (HTTP $status).');
      }
      final stream = _decodeBody(response.timeout(const Duration(seconds: 45)));
      return await parseXmltvStream(stream, DateTime.now());
    } finally {
      client.close(force: true);
    }
  }
  throw const EpgDownloadException('Guida non disponibile.');
}

Stream<List<int>> _bounded(Stream<List<int>> source, int limit) async* {
  var total = 0;
  await for (final chunk in source) {
    total += chunk.length;
    if (total > limit) {
      throw const EpgDownloadException(
        'Guida troppo grande per una lettura sicura.',
      );
    }
    yield chunk;
  }
}

Stream<List<int>> _decodeBody(Stream<List<int>> source) async* {
  final iterator = StreamIterator(_bounded(source, 128 * 1024 * 1024));
  try {
    final prefix = <int>[];
    while (prefix.length < 2 && await iterator.moveNext()) {
      prefix.addAll(iterator.current);
    }
    Stream<List<int>> joined() async* {
      yield prefix;
      while (await iterator.moveNext()) {
        yield iterator.current;
      }
    }

    final gzipBody =
        prefix.length >= 2 && prefix[0] == 0x1f && prefix[1] == 0x8b;
    final decoded = gzipBody ? joined().transform(gzip.decoder) : joined();
    yield* _bounded(decoded, 256 * 1024 * 1024);
  } finally {
    await iterator.cancel();
  }
}

/// SAX-style incremental parsing: no whole-document string or regex scans.
Future<Map<String, dynamic>> parseXmltvStream(
  Stream<List<int>> source,
  DateTime now, {
  int programmeCap = epgProgrammeCap,
}) async {
  final names = <String, dynamic>{};
  final programmes = <String, dynamic>{};
  final cap = programmeCap < 1 ? 1 : programmeCap;
  // Past includes the timeshift margin so a "+N" channel can still fill the
  // visible grid after its programmes move forward.
  final from = now
      .subtract(epgGuidePast + epgMaxTimeshift)
      .millisecondsSinceEpoch;
  final to = now.add(epgGuideFuture).millisecondsSinceEpoch;
  String? channel;
  Map<String, String>? programme;
  String? field;
  final fields = <String, StringBuffer>{};
  var rootSeen = false;
  var count = 0;
  var degraded = false;
  var capped = false;
  void end(String name) {
    if (name == field) field = null;
    if (name == 'channel') channel = null;
    if (name != 'programme') return;
    final attrs = programme;
    programme = null;
    if (attrs == null) return;
    final start = parseXmltvTime(attrs['start']);
    final stop = parseXmltvTime(attrs['stop']);
    final id = attrs['channel'];
    final title = fields['title']?.toString().trim() ?? '';
    if (start == null ||
        stop == null ||
        stop <= start ||
        id == null ||
        id.isEmpty ||
        title.isEmpty ||
        stop <= from ||
        start >= to) {
      return;
    }
    if (count >= cap) {
      degraded = true;
      capped = true;
      return;
    }
    count++;
    final description = fields['desc']?.toString().trim() ?? '';
    ((programmes[id] ??= <dynamic>[]) as List).add([
      start,
      stop,
      title,
      description.length <= epgDescriptionLimit
          ? description
          : epgClipDescription(description),
    ]);
  }

  await for (final batch
      in source
          .transform(utf8.decoder)
          .toXmlEvents(validateNesting: true, validateDocument: true)) {
    if (capped) break;
    for (final event in batch) {
      if (capped) break;
      if (event is XmlStartElementEvent) {
        final name = event.localName;
        final attrs = {for (final a in event.attributes) a.localName: a.value};
        if (name == 'tv') rootSeen = true;
        if (name == 'channel') channel = attrs['id'];
        if (name == 'programme') {
          programme = attrs;
          fields.clear();
        }
        if (name == 'display-name' && channel != null) {
          field = name;
          fields[name] = StringBuffer();
        }
        if ((name == 'title' || name == 'desc') &&
            programme != null &&
            !fields.containsKey(name)) {
          field = name;
          fields[name] = StringBuffer();
        }
        if (event.isSelfClosing) end(name);
      } else if (event is XmlTextEvent || event is XmlCDATAEvent) {
        final value = event is XmlTextEvent
            ? event.value
            : (event as XmlCDATAEvent).value;
        final buffer = fields[field];
        if (buffer != null && buffer.length < 16384) {
          buffer.write(
            value.substring(0, value.length.clamp(0, 16384 - buffer.length)),
          );
        }
      } else if (event is XmlEndElementEvent) {
        final name = event.localName;
        final channelId = channel;
        if (name == 'display-name' && channelId != null) {
          // Every display-name is kept (not only the last one).
          final value = fields[name]?.toString().trim() ?? '';
          final prior = names[channelId] as String?;
          if (value.isNotEmpty &&
              !(prior?.split(epgNameSeparator).contains(value) ?? false)) {
            names[channelId] = prior == null || prior.isEmpty
                ? value
                : '$prior$epgNameSeparator$value';
          }
        }
        end(name);
      }
    }
  }
  if (!rootSeen || (names.isEmpty && programmes.isEmpty)) {
    throw const EpgDownloadException(
      'La risposta non contiene una guida TV valida.',
    );
  }
  for (final list in programmes.values) {
    (list as List).sort((a, b) => (a[0] as int).compareTo(b[0] as int));
  }
  return {'p': programmes, 'n': names, 'd': degraded};
}

int? parseXmltvTime(String? raw) {
  if (raw == null) return null;
  final m = RegExp(
    r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*([+-]\d{2}:?\d{2}|Z)?$',
  ).firstMatch(raw.trim());
  if (m == null) return null;
  final parts = [
    for (var i = 1; i <= 6; i++) int.tryParse(m.group(i) ?? '0') ?? 0,
  ];
  final utc = DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  if (utc.year != parts[0] ||
      utc.month != parts[1] ||
      utc.day != parts[2] ||
      parts[3] > 23 ||
      parts[4] > 59 ||
      parts[5] > 59) {
    return null;
  }
  final offset = m.group(7);
  if (offset == null || offset == 'Z') return utc.millisecondsSinceEpoch;
  final clean = offset.replaceAll(':', '');
  final hours = int.parse(clean.substring(1, 3)),
      minutes = int.parse(clean.substring(3, 5));
  if (hours > 23 || minutes > 59) return null;
  return utc
      .subtract(
        Duration(
          minutes: (clean.startsWith('-') ? -1 : 1) * (hours * 60 + minutes),
        ),
      )
      .millisecondsSinceEpoch;
}
