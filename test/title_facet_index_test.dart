import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/rating_policy.dart';
import 'package:stellar_tv/services/title_facet_index.dart';

void main() {
  final index = TitleFacetIndex.instance;
  const at = 1700000000000;

  void seed() {
    index.importGenres({
      'movie:a': [16],
      'movie:b': [10751],
    }, at: at);
    index.putTmdb('movie:a', 7.1, at: at, quiet: true);
    index.putImdb(
      mediaKey: 'movie:1',
      score: const ImdbScore(7.5, votes: 900),
      at: at,
      quiet: true,
    );
    index.link(
      titleKey: 'movie:a',
      mediaKey: 'movie:1',
      tmdbId: 1,
      tmdb: 7.1,
      tmdbAt: at,
      quiet: true,
    );
  }

  // The start-up merges pass over every saved row: only real changes may be
  // queued for the save, or each launch rewrote the whole index.
  test('repeating saved values queues no rows for saving', () {
    seed();
    expect(index.pendingRows, containsAll(['movie:a', 'movie:b', 'movie:1']));
    index.pendingRows.clear();

    index.importGenres({
      'movie:a': [16],
      'movie:b': [10751],
    }, at: at + 1);
    index.putTmdb('movie:a', 7.1, at: at + 5000, quiet: true);
    index.putImdb(
      mediaKey: 'movie:1',
      score: const ImdbScore(7.5, votes: 900),
      at: at,
      quiet: true,
    );
    index.link(
      titleKey: 'movie:a',
      mediaKey: 'movie:1',
      tmdbId: 1,
      tmdb: 7.1,
      tmdbAt: at + 5000,
      quiet: true,
    );
    expect(index.pendingRows, isEmpty);
    expect(index.scoreOfTitle('movie:a'), greaterThan(0));
  });

  test('a changed score is still queued with its linked titles', () {
    seed();
    index.pendingRows.clear();
    index.putTmdb('movie:b', 6.4, at: at + 1, quiet: true);
    index.putImdb(
      mediaKey: 'movie:1',
      score: const ImdbScore(7.6, votes: 950),
      at: at + 1,
      quiet: true,
    );
    expect(index.pendingRows, {'movie:b', 'movie:1', 'movie:a'});
  });

  test('a fresh lookup with the same score renews its time', () {
    index.putTmdb('movie:d', 5.5, at: 1, quiet: true);
    expect(index.tmdbFresh('movie:d'), isFalse);
    index.putTmdb('movie:d', 5.5, quiet: true);
    expect(index.tmdbFresh('movie:d'), isTrue);
  });
}
