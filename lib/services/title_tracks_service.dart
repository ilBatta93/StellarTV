import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';
import '../models/track_languages_policy.dart';
import 'catalog_rating_service.dart';
import 'imdb_resolver.dart';
import 'subtitles_service.dart';

/// Audio and subtitle languages seen while playing a title, and whether
/// Italian subtitles exist online. Device only: these keys are outside the
/// cloud allowlist and hold no address or credential.
class TitleTracksService extends ChangeNotifier {
  TitleTracksService._();

  static final instance = TitleTracksService._();

  static const _tracksKey = 'title_tracks_v1';
  static const _onlineKey = 'subtitles_online_v1';
  static const maxEntries = 3000;

  /// Same windows as the shared check on the site.
  static const availableDays = 30;
  static const missingDays = 3;

  final Map<String, TitleTracks> _tracks = {};

  /// Key → [available, day checked].
  final Map<String, List<Object>> _online = {};
  final Map<String, Future<bool?>> _pending = {};
  Future<void>? _loading;

  static int _today() => DateTime.now().millisecondsSinceEpoch ~/ 86400000;

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = jsonDecode(prefs.getString(_tracksKey) ?? '{}');
      if (raw is Map) {
        for (final e in raw.entries) {
          if (e.value is Map<String, dynamic>) {
            _tracks['${e.key}'] = TitleTracks.fromJson(e.value);
          }
        }
      }
    } on FormatException {
      /* Start empty. */
    }
    try {
      final raw = jsonDecode(prefs.getString(_onlineKey) ?? '{}');
      if (raw is Map) {
        for (final e in raw.entries) {
          final v = e.value;
          if (v is List && v.length == 2 && v[0] is bool && v[1] is int) {
            _online['${e.key}'] = [v[0] as bool, v[1] as int];
          }
        }
      }
    } on FormatException {
      /* Start empty. */
    }
    notifyListeners();
  }

  TitleTracks of(String id) => _tracks[id] ?? TitleTracks.empty;

  /// Episodes of a series, merged.
  TitleTracks ofAll(Iterable<String> ids) =>
      mergeTitleTracks([for (final id in ids) ?_tracks[id]]);

  /// Called by the player once the tracks of a title are known. Null
  /// [subtitles] means the engine cannot list them: the last list stays.
  Future<void> record(
    String id, {
    required List<String> audio,
    List<String>? subtitles,
  }) async {
    if (id.isEmpty || (audio.isEmpty && (subtitles?.isEmpty ?? true))) return;
    await ensureLoaded();
    final previous = _tracks[id];
    final next = TitleTracks(
      audio: audio,
      subtitles: subtitles ?? previous?.subtitles ?? const [],
      seenDay: _today(),
    );
    if (previous != null &&
        listEquals(previous.audio, next.audio) &&
        listEquals(previous.subtitles, next.subtitles) &&
        previous.seenDay == next.seenDay) {
      return;
    }
    _tracks[id] = next;
    if (_tracks.length > maxEntries) {
      final oldest = _tracks.entries.toList()
        ..sort((a, b) => a.value.seenDay.compareTo(b.value.seenDay));
      for (final e in oldest.take(_tracks.length - maxEntries)) {
        _tracks.remove(e.key);
      }
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _tracksKey,
      jsonEncode({for (final e in _tracks.entries) e.key: e.value.toJson()}),
    );
  }

  static String onlineKey(String imdbId, int? season, int? episode) =>
      '$imdbId:${season ?? ''}:${episode ?? ''}';

  /// Last known answer, null when never asked or expired.
  bool? onlineSubtitles(String imdbId, {int? season, int? episode}) {
    final hit = _online[onlineKey(imdbId, season, episode)];
    if (hit == null) return null;
    final available = hit[0] as bool;
    final age = _today() - (hit[1] as int);
    return age < (available ? availableDays : missingDays) ? available : null;
  }

  /// Asks the site once per title within the windows above. Null when the
  /// answer is unknown (offline, not signed in).
  Future<bool?> checkOnlineSubtitles(
    String imdbId, {
    int? season,
    int? episode,
  }) async {
    await ensureLoaded();
    final cached = onlineSubtitles(imdbId, season: season, episode: episode);
    if (cached != null) return cached;
    final key = onlineKey(imdbId, season, episode);
    return _pending[key] ??= () async {
      try {
        final available = await SubtitlesService.available(
          imdbId: imdbId,
          season: season,
          episode: episode,
        );
        if (available == null) return null;
        _online[key] = [available, _today()];
        if (_online.length > maxEntries) {
          final oldest = _online.entries.toList()
            ..sort((a, b) => (a.value[1] as int).compareTo(b.value[1] as int));
          for (final e in oldest.take(_online.length - maxEntries)) {
            _online.remove(e.key);
          }
        }
        notifyListeners();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_onlineKey, jsonEncode(_online));
        return available;
      } finally {
        _pending.remove(key);
      }
    }();
  }

  /// The same IMDb lookup the player uses for online subtitles; the id found
  /// is remembered for the next title page and for the player.
  Future<bool?> checkTitle(
    Channel channel, {
    required bool movie,
    int? tmdbId,
    String? title,
    int? season,
    int? episode,
  }) async {
    final saved = CatalogRatingService.instance.imdbIdOf(channel);
    final imdbId =
        saved ??
        await ImdbResolver.getImdbId(
          tmdbId: tmdbId,
          title: title,
          isMovie: movie,
        );
    if (imdbId == null) return null;
    if (saved == null) {
      CatalogRatingService.instance.noteImdbId(channel, imdbId);
    }
    return checkOnlineSubtitles(imdbId, season: season, episode: episode);
  }

  @visibleForTesting
  void resetForTest() {
    _tracks.clear();
    _online.clear();
    _pending.clear();
    _loading = null;
  }
}
