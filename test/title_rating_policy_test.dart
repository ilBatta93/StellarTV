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
  group('IMDb votes', () {
    test('few enthusiastic votes do not outrank a classic', () {
      expect(weightedImdb(9.6, 40), lessThan(weightedImdb(8.4, 1200000)));
      expect(weightedImdb(8.4, 1200000), closeTo(8.4, 0.01));
      // Scores saved before vote counts existed keep their value.
      expect(weightedImdb(7.2, 0), 7.2);
    });
    test('short Italian vote labels', () {
      expect(imdbVotesLabel(830), '830');
      expect(imdbVotesLabel(48200), '48 mila');
      expect(imdbVotesLabel(1200000), '1,2 Mln');
      expect(imdbVotesLabel(2000000), '2 Mln');
    });
    test('saved scores: old bare numbers and the current form', () {
      expect(ImdbScore.fromJson(8.1), const ImdbScore(8.1, days: 30));
      // A missing rating is asked again within days, not a month.
      expect(ImdbScore.fromJson(0)?.days, 3);
      expect(
        ImdbScore.fromJson([7.5, 9100, 3]),
        const ImdbScore(7.5, votes: 9100, days: 3),
      );
      expect(ImdbScore.fromJson('x'), isNull);
    });
  });
}
