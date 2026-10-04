import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';

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
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
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
    final uri = Uri.parse(
      '${SupabaseConfig.apiBase}/opensubtitles',
    ).replace(queryParameters: {'action': 'download', 'file_id': '$fileId'});
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('download non riuscito (HTTP ${res.statusCode})');
    }
    final cues = parseSrt(res.body);
    if (cues.isEmpty) return null;
    _cache[fileId] = cues;
    return cues;
  }

  static final _timeLine = RegExp(
    r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{3})',
  );
  static final _tag = RegExp(r'<[^>]+>');

  static Duration _t(List<String> m, int o) => Duration(
    hours: int.parse(m[o]),
    minutes: int.parse(m[o + 1]),
    seconds: int.parse(m[o + 2]),
    milliseconds: int.parse(m[o + 3]),
  );

  static List<SubtitleCue> parseSrt(String raw) {
    final cues = <SubtitleCue>[];
    final blocks = raw.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'));
    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.isEmpty) continue;
      var timeIndex = 0;
      if (!_timeLine.hasMatch(lines[timeIndex]) && lines.length > 1) {
        timeIndex = 1; // salta il numero di sequenza
      }
      final match = _timeLine.firstMatch(lines[timeIndex]);
      if (match == null) continue;
      final m = [for (var i = 1; i <= 8; i++) match[i]!];
      final text = lines
          .sublist(timeIndex + 1)
          .join('\n')
          .replaceAll(_tag, '')
          .replaceAll('{\\an8}', '')
          .trim();
      if (text.isEmpty) continue;
      cues.add(SubtitleCue(_t(m, 0), _t(m, 4), text));
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
    var lo = 0;
    var hi = cues.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final cue = cues[mid];
      if (t < cue.start) {
        hi = mid - 1;
      } else if (t >= cue.end) {
        lo = mid + 1;
      } else {
        return cue.text;
      }
    }
    return null;
  }
}
