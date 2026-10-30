import 'package:stellar_tv/services/title_matching.dart';
import 'package:stellar_tv/models/rating_policy.dart';
import 'package:stellar_tv/models/episode_metadata.dart';
import 'package:stellar_tv/models/tmdb_item.dart';
import 'package:logging/logging.dart';

final Logger _logger = Logger('title_rating_policy_check');

void check(Object? actual, Object? expected) {
  if (actual != expected) throw StateError('$actual != $expected');
}

void main() {
  check(
    parseTitle('Spider.Man.No.Way.Home.2021.iTALiAN.1080p.BluRay.x264.mkv')
        .title,
    'Spider Man No Way Home',
  );
  check(parseTitle('Breaking.Bad.S01.E01.SUB.ITA.H.265').title, 'Breaking Bad');
  check(parseTitle('Breaking Bad - 1x01').title, 'Breaking Bad');
  check(parseTitle('NETFLIX | Dune (2021) 4K HDR10+ DTS 5.1').title, 'Dune');
  check(parseTitle('Dune.2021.1080p').year, '2021');
  check(parseTitle('1917').title, '1917');
  check(parseTitle('1917.2019.1080p').title, '1917');
  check(parseTitle('1917.2019.1080p').year, '2019');
  check(parseTitle('2001: A Space Odyssey').title, '2001: A Space Odyssey');
  check(parseTitle('2001: A Space Odyssey').year, null);
  for (final t in ['It', 'Up', 'Civil War', 'HD', 'Film (Director Cut)']) {
    check(parseTitle(t).title, t);
  }
  check(matchesTitle(parseTitle('Dune (2021)'), ['Dune'], '1984'), false);
  check(matchesTitle(parseTitle('Dune (2021)'), ['Dune'], '2021'), true);
  check(matchesTitle(parseTitle('Dune'), ['Dune Messiah'], '2021'), false);
  check(
    parseTitle('Dune (2021)').key('movie') ==
        parseTitle('Dune (1984)').key('movie'),
    false,
  );
  check(reliableTmdbVote(8.5, 20), 8.5);
  check(reliableTmdbVote(10, 1), 6.2);
  check(reliableTmdbVote(9.5, 5), 6.7);
  check(reliableTmdbVote(10, 0), 0.0);
  check(preferredRating(null, 8.5), 0.0);
  check(preferredRating(9.1, 8.5), 9.1);
  check(preferredRating(0, 8.5), 8.5);
  check(
    tmdbPayloadVote({
      'vote_average': 6.2,
      'vote_count': 1,
      'stellar_vote_policy': 1,
    }),
    6.2,
  );
  final item = TmdbItem.tryParse({
    'id': 1,
    'media_type': 'movie',
    'title': 'Test',
    'vote_average': 10,
    'vote_count': 1,
  });
  check(item?.voteAverage, 6.2);
  check(
    item == null ? null : TmdbItem.tryParse(item.toJson())?.voteAverage,
    6.2,
  );
  const e = EpisodeMetadata(
    seriesId: 1396,
    season: 1,
    episode: 2,
    stillPath: '/abc.jpg',
  );
  final saved = EpisodeMetadata.parse(e.toJson());
  check(saved?.key, 'tv:1396:1:2');
  check(saved?.stillUrl, 'https://image.tmdb.org/t/p/w500/abc.jpg');
  check(
    episodeArtwork(
      saved,
      'https://provider.test/e2.jpg',
      'https://provider.test/series.jpg',
    ).first,
    saved?.stillUrl,
  );
  check(
    episodeArtwork(null, 'null', 'https://provider.test/series.jpg').single,
    'https://provider.test/series.jpg',
  );
  check(
    const EpisodeMetadata(
      seriesId: 1,
      season: 1,
      episode: 1,
      stillPath: 'https://invalid.test/a.jpg',
    ).stillUrl,
    null,
  );
  _logger.info('32 controlli titoli, voti e immagini superati');
}
