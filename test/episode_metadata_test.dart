import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/episode_metadata.dart';
import 'package:stellar_tv/models/tmdb_item.dart';
import 'package:stellar_tv/services/imdb_rating_service.dart';

void main() {
  test('Episode IMDb keys cannot replace a series or another episode', () {
    expect(ImdbRatingService.episodeKey(1396, 1, 2), 'tv:1396:1:2');
    expect(
      ImdbRatingService.episodeKey(1396, 1, 2),
      isNot(ImdbRatingService.episodeKey(1396, 2, 2)),
    );
    expect(
      ImdbRatingService.episodeKey(1396, 1, 2),
      isNot(ImdbRatingService.episodeKey(1396, 1, 3)),
    );
  });
  test('Player synopsis prioritizes the episode over the series', () {
    expect(
      episodeSynopsis('Episode plot', 'Provider plot', 'Series plot'),
      'Episode plot',
    );
    expect(
      episodeSynopsis('', 'Provider plot', 'Series plot'),
      'Provider plot',
    );
    expect(episodeSynopsis(null, ' ', 'Series plot'), 'Series plot');
  });
  test(
    'Persisted episode data retains exact coordinates and fallback rating',
    () {
      const data = EpisodeMetadata(
        seriesId: 1396,
        season: 1,
        episode: 2,
        overview: 'Plot',
        tmdbRating: 8.3,
      );
      final saved = EpisodeMetadata.parse(data.toJson());
      expect(saved?.key, 'tv:1396:1:2');
      expect(saved?.tmdbRating, 8.3);
      expect(saved?.overview, 'Plot');
    },
  );
  test('Player reads a saved episode vote without queuing a request', () {
    final service = ImdbRatingService.instance;
    service.store.put('tv:1396:1:2', 9.1);
    expect(service.episodeRating(1396, 1, 2, request: false), 9.1);
    expect(service.episodeRating(1396, 1, 3, request: false), isNull);
    const title = TmdbItem(
      id: 1396,
      mediaType: 'tv',
      title: 'Title',
      overview: '',
      posterPath: null,
      backdropPath: null,
      voteAverage: 8,
      popularity: 0,
      releaseDate: '',
    );
    expect(service.ratingOf(title), isNull);
  });
}
