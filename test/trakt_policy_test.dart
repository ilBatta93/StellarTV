import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/trakt_policy.dart';
import 'package:stellar_tv/services/trakt_client.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 1, 20);

  test('session round trip and refresh window', () {
    final s = TraktSession.fromTokens(
      {
        'access_token': 'a',
        'refresh_token': 'r',
        'expires_in': 7776000,
        'created_at': t0.millisecondsSinceEpoch ~/ 1000,
      },
      clientId: 'c',
      own: true,
    )!;
    final back = TraktSession.fromJson(s.toJson())!;
    expect(back.accessToken, 'a');
    expect(back.own, isTrue);
    expect(back.expiresAt, t0.add(const Duration(days: 90)));
    expect(back.needsRefresh(t0.add(const Duration(days: 82))), isFalse);
    expect(back.needsRefresh(t0.add(const Duration(days: 84))), isTrue);
    expect(TraktSession.fromJson({'access': 'a'}), isNull);
  });

  test('episode numbers come from fields or from the name', () {
    expect(TraktPolicy.episodeNumbers(2, 5, 'x'), (season: 2, episode: 5));
    expect(TraktPolicy.episodeNumbers(null, null, 'Show S01 E03 HD'), (
      season: 1,
      episode: 3,
    ));
    expect(TraktPolicy.episodeNumbers(null, null, 'Show 2x10'), (
      season: 2,
      episode: 10,
    ));
    expect(TraktPolicy.episodeNumbers(null, null, 'Show'), isNull);
  });

  test('history body groups episodes by show and season', () {
    final body = TraktPolicy.historyBody([
      (target: const TraktTarget.movie(tmdbId: 603), at: t0),
      (
        target: const TraktTarget.episode(tmdbId: 1396, season: 1, episode: 1),
        at: t0,
      ),
      (
        target: const TraktTarget.episode(tmdbId: 1396, season: 1, episode: 2),
        at: null,
      ),
    ]);
    expect(body['movies'], [
      {
        'ids': {'tmdb': 603},
        'watched_at': '2026-11-01T20:00:00.000Z',
      },
    ]);
    final show = (body['shows'] as List).single as Map;
    expect(show['ids'], {'tmdb': 1396});
    final season = (show['seasons'] as List).single as Map;
    expect(season['number'], 1);
    expect((season['episodes'] as List).length, 2);
    expect(
      ((season['episodes'] as List)[1] as Map).containsKey('watched_at'),
      isFalse,
    );
  });

  test('scrobble body for a movie and for an episode', () {
    expect(
      TraktPolicy.scrobbleBody(const TraktTarget.movie(imdbId: 'tt1'), 12.5),
      {
        'movie': {
          'ids': {'imdb': 'tt1'},
        },
        'progress': 12.5,
      },
    );
    final ep = TraktPolicy.scrobbleBody(
      const TraktTarget.episode(tmdbId: 7, season: 2, episode: 3),
      50,
    );
    expect(ep['show'], {
      'ids': {'tmdb': 7},
    });
    expect(ep['episode'], {'season': 2, 'number': 3});
  });

  test('remote state parses watched, playback and survives JSON', () {
    final state = TraktPolicy.parseRemote(
      movies: [
        {
          'last_watched_at': '2026-10-01T10:00:00.000Z',
          'movie': {
            'title': 'Matrix',
            'year': 1999,
            'ids': {'tmdb': 603},
          },
        },
        {
          'last_watched_at': '2026-10-01T10:00:00.000Z',
          'movie': {
            'ids': {'trakt': 1},
          },
        },
      ],
      shows: [
        {
          'show': {
            'title': 'Breaking Bad',
            'year': 2008,
            'ids': {'tmdb': 1396},
          },
          'seasons': [
            {
              'number': 1,
              'episodes': [
                {'number': 1, 'last_watched_at': '2026-10-02T10:00:00.000Z'},
              ],
            },
          ],
        },
      ],
      playback: [
        {
          'progress': 42.0,
          'paused_at': '2026-10-03T10:00:00.000Z',
          'type': 'episode',
          'episode': {'season': 1, 'number': 2, 'runtime': 47},
          'show': {
            'ids': {'tmdb': 1396},
          },
        },
      ],
    );
    expect(state.watched.keys, containsAll(['movie:603', 'tv:1396:1:1']));
    expect(state.watched.length, 2);
    expect(state.movieTitles['movie:603'], 'Matrix (1999)');
    final p = state.playback['tv:1396:1:2']!;
    expect(p.progress, closeTo(0.42, 1e-9));
    expect(p.runtime, const Duration(minutes: 47));
    final back = TraktRemoteState.fromJson(state.toJson());
    expect(back.watched, state.watched);
    expect(back.playback['tv:1396:1:2']!.progress, p.progress);
    expect(back.showTitles['tv:1396'], 'Breaking Bad (2008)');
    expect(TraktRemoteState.fromJson('broken').isEmpty, isTrue);
  });

  test('a later local choice beats an older remote view', () {
    expect(
      TraktPolicy.applyRemoteWatched(remoteAt: t0, locallyWatched: false),
      isTrue,
    );
    expect(
      TraktPolicy.applyRemoteWatched(remoteAt: t0, locallyWatched: true),
      isFalse,
    );
    expect(
      TraktPolicy.applyRemoteWatched(
        remoteAt: t0,
        locallyWatched: false,
        localChoiceAt: t0.add(const Duration(minutes: 1)),
      ),
      isFalse,
    );
  });

  test('remote progress applies only when newer and unfinished', () {
    TraktPlayback p(double progress) =>
        TraktPlayback(key: 'movie:1', progress: progress, pausedAt: t0);
    bool apply(TraktPlayback remote, {DateTime? localAt, bool w = false}) =>
        TraktPolicy.applyRemoteProgress(
          remote: remote,
          locallyWatched: w,
          completionPercent: 90,
          localAt: localAt,
        );
    expect(apply(p(0.4)), isTrue);
    expect(apply(p(0.4), w: true), isFalse);
    expect(apply(p(0.95)), isFalse);
    expect(apply(p(0.001)), isFalse);
    expect(apply(p(0.4), localAt: t0), isFalse);
    expect(
      apply(p(0.4), localAt: t0.subtract(const Duration(hours: 1))),
      isTrue,
    );
  });

  test('pending changes keep only the newest choice per title', () {
    const m = TraktTarget.movie(tmdbId: 1);
    final out = TraktPolicy.compact([
      TraktPending(m, true, t0),
      TraktPending(m, false, t0.add(const Duration(minutes: 1))),
      TraktPending(const TraktTarget.movie(tmdbId: 2), true, t0),
    ]);
    expect(out.length, 2);
    expect(out.firstWhere((p) => p.target.tmdbId == 1).watched, isFalse);
    final back = TraktPending.fromJson(out.first.toJson())!;
    expect(back.target.key, out.first.target.key);
  });

  test('activity comparison', () {
    final a = TraktActivity.parse({
      'movies': {'watched_at': 'x', 'paused_at': 'y'},
      'episodes': {'watched_at': 'z', 'paused_at': 'w'},
    });
    final b = TraktActivity.parse({
      'movies': {'watched_at': 'x', 'paused_at': 'y'},
      'episodes': {'watched_at': 'z2', 'paused_at': 'w'},
    });
    expect(a.sameAs(a), isTrue);
    expect(a.sameAs(b), isFalse);
    expect(a.sameAs(null), isFalse);
  });

  test('PKCE challenge matches RFC 7636 example', () {
    expect(
      TraktClient.challengeOf('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
  });
}
