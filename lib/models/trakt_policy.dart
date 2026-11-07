/// Pure rules of the Trakt link: sessions, title identities, request bodies,
/// remote state and which side wins. No I/O.
///
/// Trakt knows titles by TMDB/IMDb ids, the app by source ids: the services
/// translate between the two, these rules only decide what to send and what
/// to apply.
library;

import 'dart:convert';

/// One profile's Trakt sign-in. Lives only in this device's secure storage:
/// Trakt rotates the refresh value at every renewal, so a copy on a second
/// device would sign one of the two out.
class TraktSession {
  const TraktSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.clientId,
    required this.own,
    this.user = '',
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  /// Trakt app that issued the sign-in: renewals must use the same one.
  final String clientId;

  /// True when issued with the user's own Trakt app keys.
  final bool own;
  final String user;

  /// Renewed a week before it expires (Trakt sign-ins last three months).
  bool needsRefresh(DateTime now) => !now.toUtc().isBefore(
    expiresAt.toUtc().subtract(const Duration(days: 7)),
  );

  TraktSession copyWith({String? user}) => TraktSession(
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresAt: expiresAt,
    clientId: clientId,
    own: own,
    user: user ?? this.user,
  );

  Map<String, dynamic> toJson() => {
    'access': accessToken,
    'refresh': refreshToken,
    'expires': expiresAt.toUtc().toIso8601String(),
    'client': clientId,
    'own': own,
    'user': user,
  };

  static TraktSession? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final access = raw['access'], refresh = raw['refresh'];
    final client = raw['client'];
    final expires = DateTime.tryParse(raw['expires']?.toString() ?? '');
    if (access is! String || access.isEmpty) return null;
    if (refresh is! String || refresh.isEmpty) return null;
    if (client is! String || client.isEmpty || expires == null) return null;
    return TraktSession(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: expires,
      clientId: client,
      own: raw['own'] == true,
      user: raw['user'] is String ? raw['user'] as String : '',
    );
  }

  /// Session from the tokens Trakt returns ({access_token, refresh_token,
  /// expires_in, created_at}).
  static TraktSession? fromTokens(
    Object? raw, {
    required String clientId,
    required bool own,
    String user = '',
  }) {
    if (raw is! Map) return null;
    final access = raw['access_token'], refresh = raw['refresh_token'];
    if (access is! String || access.isEmpty) return null;
    if (refresh is! String || refresh.isEmpty) return null;
    final created = (raw['created_at'] as num?)?.toInt();
    final expiresIn = (raw['expires_in'] as num?)?.toInt() ?? 7776000;
    final start = created != null && created > 0
        ? DateTime.fromMillisecondsSinceEpoch(created * 1000, isUtc: true)
        : DateTime.now().toUtc();
    return TraktSession(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: start.add(Duration(seconds: expiresIn)),
      clientId: clientId,
      own: own,
      user: user,
    );
  }
}

/// A title as Trakt knows it: a movie, or one episode of a show.
class TraktTarget {
  const TraktTarget.movie({this.tmdbId, this.imdbId})
    : movie = true,
      season = null,
      episode = null;
  const TraktTarget.episode({
    required int this.tmdbId,
    required int this.season,
    required int this.episode,
  }) : movie = false,
       imdbId = null;

  final bool movie;

  /// Movie id, or the show id for an episode.
  final int? tmdbId;
  final String? imdbId;
  final int? season;
  final int? episode;

  bool get valid => movie
      ? (tmdbId != null && tmdbId! > 0) ||
            (imdbId != null && RegExp(r'^tt\d+$').hasMatch(imdbId!))
      : tmdbId != null && tmdbId! > 0 && season! >= 0 && episode! >= 1;

  /// Same keys as [TraktRemoteState]: `movie:<tmdb>` or `tv:<tmdb>:<s>:<e>`.
  /// A movie known only by IMDb id uses `imdb:<id>`.
  String get key => movie
      ? (tmdbId != null ? 'movie:$tmdbId' : 'imdb:$imdbId')
      : 'tv:$tmdbId:$season:$episode';

  Map<String, dynamic> get ids => {
    if (tmdbId != null) 'tmdb': tmdbId,
    if (tmdbId == null && imdbId != null) 'imdb': imdbId,
  };

  Map<String, dynamic> toJson() => {
    'm': movie,
    if (tmdbId != null) 't': tmdbId,
    if (imdbId != null) 'i': imdbId,
    if (season != null) 's': season,
    if (episode != null) 'e': episode,
  };

  static TraktTarget? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final tmdb = (raw['t'] as num?)?.toInt();
    final TraktTarget target;
    if (raw['m'] == true) {
      target = TraktTarget.movie(
        tmdbId: tmdb,
        imdbId: raw['i'] is String ? raw['i'] as String : null,
      );
    } else {
      final s = (raw['s'] as num?)?.toInt(), e = (raw['e'] as num?)?.toInt();
      if (tmdb == null || s == null || e == null) return null;
      target = TraktTarget.episode(tmdbId: tmdb, season: s, episode: e);
    }
    return target.valid ? target : null;
  }
}

/// A change waiting to reach Trakt (kept while offline).
class TraktPending {
  const TraktPending(this.target, this.watched, this.at);
  final TraktTarget target;

  /// True: add a view at [at]. False: remove its views.
  final bool watched;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'x': target.toJson(),
    'w': watched,
    'at': at.toUtc().toIso8601String(),
  };

  static TraktPending? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final target = TraktTarget.fromJson(raw['x']);
    final at = DateTime.tryParse(raw['at']?.toString() ?? '');
    if (target == null || at == null || raw['w'] is! bool) return null;
    return TraktPending(target, raw['w'] as bool, at);
  }
}

/// A paused title on Trakt: where to resume and when it was paused.
class TraktPlayback {
  const TraktPlayback({
    required this.key,
    required this.progress,
    required this.pausedAt,
    this.runtime,
  });
  final String key;

  /// 0..1 share of the runtime.
  final double progress;
  final DateTime pausedAt;
  final Duration? runtime;

  Map<String, dynamic> toJson() => {
    'k': key,
    'p': progress,
    'at': pausedAt.toUtc().toIso8601String(),
    if (runtime != null) 'r': runtime!.inSeconds,
  };

  static TraktPlayback? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = DateTime.tryParse(raw['at']?.toString() ?? '');
    final p = (raw['p'] as num?)?.toDouble();
    if (raw['k'] is! String || at == null || p == null) return null;
    final r = (raw['r'] as num?)?.toInt();
    return TraktPlayback(
      key: raw['k'] as String,
      progress: p,
      pausedAt: at,
      runtime: r != null && r > 0 ? Duration(seconds: r) : null,
    );
  }
}

/// What Trakt holds for one profile: last view of every watched movie and
/// episode, paused titles, and the names of watched shows (to recognize a
/// show the catalog has not linked to TMDB yet).
class TraktRemoteState {
  TraktRemoteState({
    Map<String, DateTime>? watched,
    Map<String, TraktPlayback>? playback,
    Map<String, String>? showTitles,
    Map<String, String>? movieTitles,
  }) : watched = watched ?? {},
       playback = playback ?? {},
       showTitles = showTitles ?? {},
       movieTitles = movieTitles ?? {};

  final Map<String, DateTime> watched;
  final Map<String, TraktPlayback> playback;

  /// `tv:<tmdb>` -> "Title (year)" as Trakt names it.
  final Map<String, String> showTitles;

  /// `movie:<tmdb>` -> "Title (year)".
  final Map<String, String> movieTitles;

  bool get isEmpty => watched.isEmpty && playback.isEmpty;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'w': {
      for (final e in watched.entries) e.key: e.value.toUtc().toIso8601String(),
    },
    'p': [for (final p in playback.values) p.toJson()],
    'st': showTitles,
    'mt': movieTitles,
  };

  static TraktRemoteState fromJson(Object? raw) {
    final state = TraktRemoteState();
    if (raw is! Map || raw['v'] != 1) return state;
    final w = raw['w'];
    if (w is Map) {
      for (final e in w.entries) {
        final at = DateTime.tryParse(e.value?.toString() ?? '');
        if (e.key is String && at != null) state.watched[e.key as String] = at;
      }
    }
    final p = raw['p'];
    if (p is List) {
      for (final item in p) {
        final playback = TraktPlayback.fromJson(item);
        if (playback != null) state.playback[playback.key] = playback;
      }
    }
    for (final (field, into) in [
      ('st', state.showTitles),
      ('mt', state.movieTitles),
    ]) {
      final titles = raw[field];
      if (titles is! Map) continue;
      for (final e in titles.entries) {
        if (e.key is String && e.value is String) {
          into[e.key as String] = e.value as String;
        }
      }
    }
    return state;
  }
}

/// Activity stamps from `/sync/last_activities`: when any of them moves the
/// remote state is downloaded again.
class TraktActivity {
  const TraktActivity(this.stamps);
  final Map<String, String> stamps;

  static const _fields = [
    ('movies', 'watched_at'),
    ('movies', 'paused_at'),
    ('episodes', 'watched_at'),
    ('episodes', 'paused_at'),
  ];

  static TraktActivity parse(Object? raw) {
    final stamps = <String, String>{};
    if (raw is Map) {
      for (final (group, field) in _fields) {
        final g = raw[group];
        final v = g is Map ? g[field] : null;
        if (v is String) stamps['$group.$field'] = v;
      }
    }
    return TraktActivity(stamps);
  }

  bool sameAs(TraktActivity? other) {
    if (other == null || other.stamps.length != stamps.length) return false;
    for (final e in stamps.entries) {
      if (other.stamps[e.key] != e.value) return false;
    }
    return stamps.isNotEmpty;
  }
}

class TraktPolicy {
  const TraktPolicy._();

  /// Pause points under this share are not worth a resume on Trakt.
  static const minProgress = 0.01;

  /// A view reported as finished counts on Trakt only from 80%.
  static const finishedPercent = 90.0;

  /// Share of the runtime as Trakt wants it (0-100, one decimal).
  static double percent(Duration position, Duration duration) {
    if (duration <= Duration.zero) return 0;
    final p = position.inMilliseconds * 100 / duration.inMilliseconds;
    return (p.clamp(0, 100) * 10).round() / 10;
  }

  /// Season and episode of an episode: the source fields first, then a
  /// "S01E02" / "1x02" tag in its name.
  static ({int season, int episode})? episodeNumbers(
    int? season,
    int? episode,
    String name,
  ) {
    if (season == null || episode == null) {
      final match = RegExp(
        r'\bS(\d{1,3})\s*[. _-]*E(\d{1,4})\b|\b(\d{1,3})x(\d{1,4})\b',
        caseSensitive: false,
      ).firstMatch(name);
      if (match != null) {
        season ??= int.tryParse(match[1] ?? match[3] ?? '');
        episode ??= int.tryParse(match[2] ?? match[4] ?? '');
      }
    }
    if (season == null || episode == null || season < 0 || episode < 1) {
      return null;
    }
    return (season: season, episode: episode);
  }

  /// `/sync/history` and `/sync/history/remove` body. [at] is null for a
  /// removal.
  static Map<String, dynamic> historyBody(
    Iterable<({TraktTarget target, DateTime? at})> items,
  ) {
    final movies = <Map<String, dynamic>>[];
    final shows = <int, Map<int, List<Map<String, dynamic>>>>{};
    for (final item in items) {
      final t = item.target;
      if (!t.valid) continue;
      final stamp = item.at == null
          ? null
          : {'watched_at': item.at!.toUtc().toIso8601String()};
      if (t.movie) {
        movies.add({'ids': t.ids, ...?stamp});
      } else {
        ((shows[t.tmdbId!] ??= {})[t.season!] ??= []).add({
          'number': t.episode,
          ...?stamp,
        });
      }
    }
    return {
      if (movies.isNotEmpty) 'movies': movies,
      if (shows.isNotEmpty)
        'shows': [
          for (final show in shows.entries)
            {
              'ids': {'tmdb': show.key},
              'seasons': [
                for (final season in show.value.entries)
                  {'number': season.key, 'episodes': season.value},
              ],
            },
        ],
    };
  }

  /// `/scrobble/{start,pause,stop}` body.
  static Map<String, dynamic> scrobbleBody(TraktTarget t, double percent) => {
    if (t.movie)
      'movie': {'ids': t.ids}
    else ...{
      'show': {
        'ids': {'tmdb': t.tmdbId},
      },
      'episode': {'season': t.season, 'number': t.episode},
    },
    'progress': percent,
  };

  static String _titleOf(Object? item) {
    if (item is! Map) return '';
    final title = item['title'];
    final year = item['year'];
    if (title is! String || title.isEmpty) return '';
    return year is num ? '$title (${year.toInt()})' : title;
  }

  static int? _tmdbOf(Object? item) {
    if (item is! Map) return null;
    final ids = item['ids'];
    final id = ids is Map ? ids['tmdb'] : null;
    return id is num && id > 0 ? id.toInt() : null;
  }

  /// [parseRemote] from the response texts. Run in an isolate: a long
  /// Trakt history is several MB of JSON.
  static TraktRemoteState parseRemoteText(
    String? movies,
    String? shows,
    String? playback,
  ) {
    Object? decode(String? text) {
      if (text == null || text.isEmpty) return null;
      try {
        return jsonDecode(text);
      } catch (_) {
        return null;
      }
    }

    return parseRemote(
      movies: decode(movies),
      shows: decode(shows),
      playback: decode(playback),
    );
  }

  /// Remote state from `/sync/watched/movies`, `/sync/watched/shows` and
  /// `/sync/playback`. Items without a TMDB id are skipped: the catalog is
  /// joined to TMDB only.
  static TraktRemoteState parseRemote({
    required Object? movies,
    required Object? shows,
    required Object? playback,
  }) {
    final state = TraktRemoteState();
    if (movies is List) {
      for (final row in movies) {
        if (row is! Map) continue;
        final id = _tmdbOf(row['movie']);
        final at = DateTime.tryParse(row['last_watched_at']?.toString() ?? '');
        if (id == null || at == null) continue;
        state.watched['movie:$id'] = at;
        final title = _titleOf(row['movie']);
        if (title.isNotEmpty) state.movieTitles['movie:$id'] = title;
      }
    }
    if (shows is List) {
      for (final row in shows) {
        if (row is! Map) continue;
        final id = _tmdbOf(row['show']);
        if (id == null) continue;
        final title = _titleOf(row['show']);
        if (title.isNotEmpty) state.showTitles['tv:$id'] = title;
        final seasons = row['seasons'];
        if (seasons is! List) continue;
        for (final season in seasons) {
          if (season is! Map || season['number'] is! num) continue;
          final s = (season['number'] as num).toInt();
          final episodes = season['episodes'];
          if (episodes is! List) continue;
          for (final ep in episodes) {
            if (ep is! Map || ep['number'] is! num) continue;
            final at = DateTime.tryParse(
              ep['last_watched_at']?.toString() ?? '',
            );
            if (at == null) continue;
            state.watched['tv:$id:$s:${(ep['number'] as num).toInt()}'] = at;
          }
        }
      }
    }
    if (playback is List) {
      for (final row in playback) {
        if (row is! Map) continue;
        final p = (row['progress'] as num?)?.toDouble();
        final at = DateTime.tryParse(row['paused_at']?.toString() ?? '');
        if (p == null || at == null) continue;
        String? key;
        Object? media;
        if (row['type'] == 'movie') {
          media = row['movie'];
          final id = _tmdbOf(media);
          if (id != null) key = 'movie:$id';
          final title = _titleOf(media);
          if (id != null && title.isNotEmpty) {
            state.movieTitles['movie:$id'] = title;
          }
        } else if (row['type'] == 'episode') {
          media = row['episode'];
          final id = _tmdbOf(row['show']);
          final ep = row['episode'];
          if (id != null &&
              ep is Map &&
              ep['season'] is num &&
              ep['number'] is num) {
            key =
                'tv:$id:${(ep['season'] as num).toInt()}:'
                '${(ep['number'] as num).toInt()}';
            final title = _titleOf(row['show']);
            if (title.isNotEmpty) state.showTitles['tv:$id'] = title;
          }
        }
        if (key == null) continue;
        final runtime = media is Map ? media['runtime'] : null;
        final playbackItem = TraktPlayback(
          key: key,
          progress: (p / 100).clamp(0.0, 1.0),
          pausedAt: at,
          runtime: runtime is num && runtime > 0
              ? Duration(minutes: runtime.toInt())
              : null,
        );
        final previous = state.playback[key];
        if (previous == null || at.isAfter(previous.pausedAt)) {
          state.playback[key] = playbackItem;
        }
      }
    }
    return state;
  }

  /// A view on Trakt marks the title watched here unless this device already
  /// counts it as watched, or a later choice made here (for example "segna
  /// come non visto") is newer than that view.
  static bool applyRemoteWatched({
    required DateTime remoteAt,
    required bool locallyWatched,
    DateTime? localChoiceAt,
  }) {
    if (locallyWatched) return false;
    if (localChoiceAt != null && !remoteAt.isAfter(localChoiceAt)) {
      return false;
    }
    return true;
  }

  /// A pause point on Trakt becomes the resume point here when it is newer
  /// than the last local view and not already past the completion share.
  static bool applyRemoteProgress({
    required TraktPlayback remote,
    required bool locallyWatched,
    required int completionPercent,
    DateTime? localAt,
    DateTime? removedAt,
  }) {
    if (locallyWatched) return false;
    if (remote.progress < minProgress) return false;
    if (remote.progress * 100 >= completionPercent) return false;
    if (localAt != null && !remote.pausedAt.isAfter(localAt)) return false;
    if (removedAt != null && !remote.pausedAt.isAfter(removedAt)) return false;
    return true;
  }

  /// A title marked watched by hand is sent only when Trakt does not count
  /// it as watched yet: a second mark would add a second view there.
  static bool pushWatched(TraktTarget target, TraktRemoteState remote) =>
      !remote.watched.containsKey(target.key);

  /// Pending changes to send, newest choice per title only.
  static List<TraktPending> compact(Iterable<TraktPending> pending) {
    final byKey = <String, TraktPending>{};
    for (final p in pending) {
      final old = byKey[p.target.key];
      if (old == null || !p.at.isBefore(old.at)) byKey[p.target.key] = p;
    }
    return byKey.values.toList()..sort((a, b) => a.at.compareTo(b.at));
  }
}
