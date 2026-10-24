import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/title_matching.dart';
import 'package:stellar_tv/models/rating_policy.dart';
import 'package:stellar_tv/models/episode_metadata.dart';

import 'title_rating_policy_check.dart' as checks;

void main() {
  test('dotted title and technical tags', () {
    expect(
      parseTitle('Breaking.Bad.S01.E01.SUB.ITA.H.265').title,
      'Breaking Bad',
    );
  });
  test('numeric titles are preserved', () {
    expect(parseTitle('2001: A Space Odyssey').title, '2001: A Space Odyssey');
  });
  test('remake years remain distinct', () {
    expect(
      parseTitle('Dune (2021)').key('movie'),
      isNot(parseTitle('Dune (1984)').key('movie')),
    );
  });
  test('at least 20 TMDB votes preserve the value', () {
    expect(reliableTmdbVote(8.5, 20), 8.5);
  });
  test('below 20 votes are weighted', () {
    expect(reliableTmdbVote(10, 1), 6.2);
  });
  test('zero votes have no rating', () {
    expect(reliableTmdbVote(10, 0), 0);
  });
  test('IMDb pending never exposes temporary TMDB', () {
    expect(preferredRating(null, 8.5), 0);
  });
  test('IMDb wins over TMDB', () {
    expect(preferredRating(9.1, 8.5), 9.1);
  });
  test('confirmed IMDb absence uses TMDB', () {
    expect(preferredRating(0, 8.5), 8.5);
  });
  test('episode image precedes provider and series', () {
    const e = EpisodeMetadata(
      seriesId: 1396,
      season: 1,
      episode: 2,
      stillPath: '/abc.jpg',
    );
    expect(
      episodeArtwork(
        e,
        'https://provider.test/e2.jpg',
        'https://provider.test/series.jpg',
      ).first,
      'https://image.tmdb.org/t/p/w500/abc.jpg',
    );
  });
  test('model cache and matching regressions', checks.main);
}
