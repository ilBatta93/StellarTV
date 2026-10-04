import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/supabase_config.dart';
import '../models/channel.dart';
import '../models/content_type.dart';

/// Kids profile filter based on TMDB age certifications (G, PG, TV-Y,
/// TV-Y7...) checked by the app server, plus a list of banned keywords.
/// Verdicts are cached on the device; unknown titles stay hidden until
/// they are checked.
class KidsContentService {
  static const _cacheKey = 'kids_verdicts_v1';
  static const _batchSize = 40;

  static final bannedKeywords = RegExp(
    r'\b(xxx|porn\w*|sex\w*|sesso|eroti\w*|adult[io]?|nud[oi]ty?|horror|'
    r'terror|slasher|gore|zombie\w*|killer|assassin\w*|omicid\w*|murder|'
    r'drug|droga|narcos|gangster|mafia|violen\w*|tortur\w*|satan\w*|'
    r'demon\w*|esorcist\w*|exorcist|vm\s?18|vm\s?14)\b|18\s*\+',
    caseSensitive: false,
  );

  final Map<String, bool> _verdicts = {};
  final Set<String> _pending = {};
  bool _loaded = false;
  bool _running = false;
  void Function()? onVerdicts;

  static String keyOf(Channel c) {
    final type = c.type == ContentType.movie ? 'movie' : 'tv';
    final title = (c.seriesName?.isNotEmpty == true ? c.seriesName! : c.name);
    final norm = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9à-ÿ]+'), ' ')
        .trim();
    return '$type:$norm';
  }

  static String _titleOf(Channel c) =>
      c.seriesName?.isNotEmpty == true ? c.seriesName! : c.name;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      map.forEach((k, v) {
        if (v is bool) _verdicts[k] = v;
      });
    } catch (_) {}
  }

  /// True when the item can be shown in a kids profile.
  bool isKidsContent(Channel item) {
    if (bannedKeywords.hasMatch('${item.name} ${item.seriesName ?? ''} ${item.plot ?? ''}')) {
      return false;
    }
    return _verdicts[keyOf(item)] == true;
  }

  bool isKnown(Channel item) => _verdicts.containsKey(keyOf(item));

  /// Queues unknown titles and checks them in the background.
  void request(Iterable<Channel> items) {
    for (final c in items) {
      if (c.type != ContentType.movie && c.type != ContentType.series) continue;
      final key = keyOf(c);
      if (_verdicts.containsKey(key)) continue;
      if (bannedKeywords.hasMatch(_titleOf(c))) {
        _verdicts[key] = false;
        continue;
      }
      _pending.add('${key.split(':').first}\u0000${_titleOf(c)}');
    }
    if (!_running) unawaited(_run());
  }

  Future<void> _run() async {
    _running = true;
    try {
      while (_pending.isNotEmpty) {
        final batch = _pending.take(_batchSize).toList();
        _pending.removeAll(batch);
        final items = [
          for (final b in batch)
            {'type': b.split('\u0000').first, 'title': b.split('\u0000').last},
        ];
        try {
          final res = await http
              .post(Uri.parse('${SupabaseConfig.apiBase}/kids-check'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({'items': items}))
              .timeout(const Duration(seconds: 60));
          if (res.statusCode != 200) {
            await Future<void>.delayed(const Duration(seconds: 20));
            continue;
          }
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          for (final r in (body['results'] as List? ?? const [])) {
            if (r is! Map || r['is_kids'] is! bool) continue;
            final norm = (r['title'] as String)
                .toLowerCase()
                .replaceAll(RegExp(r'[^a-z0-9à-ÿ]+'), ' ')
                .trim();
            _verdicts['${r['type']}:$norm'] = r['is_kids'] as bool;
          }
          await _save();
          onVerdicts?.call();
        } catch (_) {
          await Future<void>.delayed(const Duration(seconds: 20));
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(_verdicts));
  }
}
