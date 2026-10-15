import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/providers/reactions_provider.dart';
import 'package:stellar_tv/models/tmdb_item.dart';

const item = TmdbItem(
  id: 1,
  mediaType: 'movie',
  title: 'Test',
  overview: '',
  posterPath: null,
  backdropPath: null,
  voteAverage: 0,
  popularity: 0,
  releaseDate: '',
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'Reactions are private per profile and persist; each action pushes',
    () async {
      final p = ReactionsProvider();
      var pushes = 0;
      p.onSaved = () => pushes++;
      await p.switchProfile('a');
      await p.setVote(item, 1);
      expect(p.liked.single.key, item.key);
      expect(pushes, 1);
      await p.switchProfile('b');
      expect(p.vote(item), 0);
      await p.setVote(item, -1);
      expect(p.disliked, contains(item.key));
      await p.switchProfile('a');
      expect(p.vote(item), 1);
      await p.setVote(item, 1);
      expect(p.vote(item), 0);
      expect(pushes, 3);
      final restored = ReactionsProvider();
      await restored.switchProfile('b');
      expect(restored.vote(item), -1);
      restored.dispose();
      p.dispose();
    },
  );
  test(
    'Neutral tombstone wins older remote like, preserving other profiles',
    () {
      final local = jsonEncode({
        'a': {
          'movie_1': {'vote': 0, 'at': '2026-10-15T11:00:00Z'},
        },
      });
      final remote = jsonEncode({
        'a': {
          'movie_1': {'vote': 1, 'at': '2026-10-15T10:00:00Z'},
        },
        'b': {
          'movie_2': {'vote': -1, 'at': '2026-10-15T10:00:00Z'},
        },
      });
      final merged = jsonDecode(ReactionsProvider.merge(local, remote));
      expect(merged['a']['movie_1']['vote'], 0);
      expect(merged['b']['movie_2']['vote'], -1);
    },
  );
}
