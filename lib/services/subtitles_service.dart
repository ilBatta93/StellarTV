import 'foreground_http_client.dart';

import 'dart:convert';

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

final _foregroundHttp = ForegroundHttpClient();

class SubtitleCue {
  final Duration start;
  final Duration end;
  final String text;
  const SubtitleCue(this.start, this.end, this.text);

  bool contains(Duration t) => t >= start && t < end;
}

class OnlineSubtitle {
  final int fileId;
  final String release;
  final int downloads;
  final bool hearingImpaired;

  const OnlineSubtitle({
    required this.fileId,
    required this.release,
    required this.downloads,
    required this.hearingImpaired,
  });
}

/// Sottotitoli in italiano da OpenSubtitles, tramite il proxy cloud
/// (la chiave API non è nell'app). Ogni errore solleva un'eccezione con
/// un messaggio leggibile, mostrato nel player.
class SubtitlesService {
  static final Map<int, List<SubtitleCue>> _cache = {};
  static final Map<String, List<SubtitleCue>> _memByKey = {};

  static Future<File> _offlineFile(String key) async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/subtitles',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${dir.path}/$safe.srt');
  }

  /// Recupera i sottotitoli italiani: prima dal disco (offline), poi dal
  /// cloud, che usa una cache condivisa e una catena di provider gratuiti
  /// (Wyzie, SubDL) con OpenSubtitles come ultimo tentativo.
  static Future<List<SubtitleCue>> fetch({
    required String imdbId,
    int? season,
    int? episode,
    String language = 'it',
    bool refresh = false,
    int variant = 0,
    String? movieHash,
    int? byteSize,
  }) async {
    if ((season == null) != (episode == null)) {
      throw Exception('stagione ed episodio mancanti');
    }
    final key =
        'v2_${imdbId}_${season ?? ''}_${episode ?? ''}_${language}_$variant'
        '${movieHash == null ? '' : '_h$movieHash'}';
    final mem = _memByKey[key];
    if (!refresh && mem != null) return mem;
    try {
      final f = await _offlineFile(key);
      if (!refresh && await f.exists()) {
        final cues = parseSrt(await f.readAsString());
        if (cues.isNotEmpty) return _memByKey[key] = cues;
      }
    } catch (_) {}
    final uri = Uri.parse('${SupabaseConfig.apiBase}/subtitles').replace(
      queryParameters: {
        'imdb_id': imdbId,
        if (season != null && episode != null) 'season': '$season',
        if (season != null && episode != null) 'episode': '$episode',
        'language': language,
        'variant': '$variant',
        if (movieHash != null && byteSize != null) 'moviehash': movieHash,
        if (movieHash != null && byteSize != null) 'bytesize': '$byteSize',
      },
    );
    final res = await _foregroundHttp
        .get(uri, headers: _authHeaders())
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 401) {
      throw Exception('accedi al tuo account per i sottotitoli');
    }
    if (res.statusCode == 404) {
      throw Exception('nessun sottotitolo italiano disponibile');
    }
    if (res.statusCode != 200) {
      throw Exception('recupero non riuscito (HTTP ${res.statusCode})');
    }
    final body = utf8.decode(res.bodyBytes, allowMalformed: true);
    final cues = parseSrt(body);
    if (cues.isEmpty) throw Exception('file dei sottotitoli non valido');
    try {
      await (await _offlineFile(key)).writeAsString(body, flush: true);
    } catch (_) {}
    return _memByKey[key] = cues;
  }

  /// The subtitle service is reserved to signed-in accounts.
  static Map<String, String> _authHeaders() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return token == null ? const {} : {'Authorization': 'Bearer $token'};
  }

  static Future<List<OnlineSubtitle>> search({
    required String imdbId,
    int? season,
    int? episode,
  }) async {
    final isEpisode = season != null && episode != null;
    final uri = Uri.parse('${SupabaseConfig.apiBase}/opensubtitles').replace(
      queryParameters: {
        'action': 'search',
        'imdb_id': imdbId,
        'type': isEpisode ? 'episode' : 'movie',
        if (isEpisode) 'season': '$season',
        if (isEpisode) 'episode': '$episode',
      },
    );
    final res = await _foregroundHttp
        .get(uri, headers: _authHeaders())
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('ricerca non riuscita (HTTP ${res.statusCode})');
    }
    final list = (jsonDecode(res.body) as Map)['results'];
    if (list is! List) return const [];
    return [
      for (final r in list)
        if (r is Map && r['file_id'] is num)
          OnlineSubtitle(
            fileId: (r['file_id'] as num).toInt(),
            release: '${r['release'] ?? ''}',
            downloads: (r['downloads'] as num?)?.toInt() ?? 0,
            hearingImpaired: r['hearing_impaired'] == true,
          ),
    ];
  }

  /// Scarica e interpreta il file .srt. Il risultato resta in memoria per
  /// tutta la sessione, così cambiare episodio e tornare indietro non
  /// consuma un altro download giornaliero.
  static Future<List<SubtitleCue>?> download(int fileId) async {
    final cached = _cache[fileId];
    if (cached != null) return cached;
    final uri = Uri.parse('${SupabaseConfig.apiBase}/opensubtitles')
        .replace(queryParameters: {'action': 'download', 'file_id': '$fileId'});
    final res = await _foregroundHttp
        .get(uri, headers: _authHeaders())
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('download non riuscito (HTTP ${res.statusCode})');
    }
    final cues = parseSrt(utf8.decode(res.bodyBytes, allowMalformed: true));
    if (cues.isEmpty) return null;
    _cache[fileId] = cues;
    return cues;
  }

  static final _timeLine = RegExp(
    r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{3})',
  );
  static final _maxEnds = Expando<List<Duration>>();

  static final _tag = RegExp(r'<[^>]+>');

  static Duration _t(List<String> m, int o) => Duration(
    hours: int.parse(m[o]),
    minutes: int.parse(m[o + 1]),
    seconds: int.parse(m[o + 2]),
    milliseconds: int.parse(m[o + 3]),
  );

  static List<SubtitleCue> parseSrt(String raw) {
    final cues = <SubtitleCue>[];
    final blocks = raw
        .replaceAll('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split(RegExp(r'\n\s*\n'));
    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.isEmpty) continue;
      var timeIndex = 0;
      if (!_timeLine.hasMatch(lines[timeIndex]) && lines.length > 1) {
        timeIndex = 1; // salta il numero di sequenza
      }
      final match = _timeLine.firstMatch(lines[timeIndex]);
      if (match == null) continue;
      final m = [for (var i = 1; i <= 8; i++) match.group(i) ?? '0'];
      final text = lines
          .sublist(timeIndex + 1)
          .join('\n')
          .replaceAll(_tag, '')
          .replaceAll('{\\an8}', '')
          .trim();
      if (text.isEmpty) continue;
      final start = _t(m, 0);
      final end = _t(m, 4);
      if (end <= start) continue;
      cues.add(SubtitleCue(start, end, text));
    }
    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  /// Testo da mostrare a [position], applicando il [delay] impostato
  /// dall'utente (positivo = sottotitoli in ritardo).
  static String? cueAt(
    List<SubtitleCue> cues,
    Duration position,
    Duration delay,
  ) {
    final t = position - delay;
    // Upper bound by start only: end times are not monotonic when cues
    // overlap (dialogue plus signs), so binary-searching ends drops text.
    var lo = 0;
    var hi = cues.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (cues[mid].start <= t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    var maxEnds = _maxEnds[cues];
    if (maxEnds == null) {
      var end = Duration.zero;
      maxEnds = [for (final cue in cues) (end = cue.end > end ? cue.end : end)];
      _maxEnds[cues] = maxEnds;
    }
    final active = <String>[];
    for (var i = lo - 1; i >= 0 && maxEnds[i] > t; i--) {
      if (cues[i].contains(t) && !active.contains(cues[i].text)) {
        active.add(cues[i].text);
      }
    }
    return active.isEmpty ? null : active.reversed.join('\n');
  }
}
