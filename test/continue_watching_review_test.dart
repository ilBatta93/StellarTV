import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/history_entry.dart';
import 'package:stellar_tv/models/tmdb_item.dart';
import 'package:stellar_tv/providers/discover_provider.dart';
import 'package:stellar_tv/services/next_episode_memory.dart';
import 'package:stellar_tv/services/unattended_playback.dart';

TmdbItem _item(int id) => TmdbItem(
  id: id,
  mediaType: 'movie',
  title: 'T$id',
  overview: '',
  posterPath: null,
  backdropPath: null,
  voteAverage: 0,
  popularity: 0,
  releaseDate: '',
);

HistoryEntry _episode(Duration position) => HistoryEntry(
  contentId: 'ep1',
  type: ContentType.series,
  title: 'Serie S01E01',
  posterUrl: '',
  group: '',
  position: position,
  duration: const Duration(minutes: 40),
  lastWatchedAt: DateTime.utc(2026, 11, 1, 22),
);

void main() {
  group('autoplay while nobody watches', () {
    setUp(() {
      UnattendedPlayback.userActed();
      UnattendedPlayback.playerOpened();
    });

    test('stops after three automatic episodes in a row', () {
      for (var i = 0; i < UnattendedPlayback.maxAutoAdvances; i++) {
        expect(UnattendedPlayback.mayAdvance, isTrue);
        UnattendedPlayback.autoAdvanced();
        UnattendedPlayback.playerOpened();
      }
      expect(UnattendedPlayback.mayAdvance, isFalse);
    });

    test('a key press or a title opened by hand starts afresh', () {
      for (var i = 0; i < UnattendedPlayback.maxAutoAdvances; i++) {
        UnattendedPlayback.autoAdvanced();
        UnattendedPlayback.playerOpened();
      }
      UnattendedPlayback.userActed();
      expect(UnattendedPlayback.mayAdvance, isTrue);

      for (var i = 0; i < UnattendedPlayback.maxAutoAdvances; i++) {
        UnattendedPlayback.autoAdvanced();
        UnattendedPlayback.playerOpened();
      }
      UnattendedPlayback.playerOpened();
      expect(UnattendedPlayback.mayAdvance, isTrue);
    });
  });

  group('recommendations', () {
    test('titles suggested by more seeds come first', () {
      final ranked = rankRecommendations([
        [_item(1), _item(2), _item(3)],
        [_item(4), _item(3)],
      ], const {});
      expect(ranked.first.id, 3);
      expect(ranked.map((i) => i.id), [3, 1, 4, 2]);
    });

    test('excluded titles and duplicates are dropped, length is capped', () {
      final ranked = rankRecommendations(
        [
          [for (var i = 0; i < 30; i++) _item(i)],
          [for (var i = 20; i < 60; i++) _item(i)],
        ],
        {_item(0).key},
        limit: 40,
      );
      expect(ranked, hasLength(40));
      expect(ranked.any((i) => i.id == 0), isFalse);
      expect(ranked.map((i) => i.key).toSet(), hasLength(40));
    });
  });

  group('next episode memory', () {
    test('a newer view is a new question', () {
      final a = NextEpisodeMemory.keyOf('p', _episode(Duration.zero));
      final b = NextEpisodeMemory.keyOf(
        'p',
        _episode(const Duration(minutes: 40)),
      );
      expect(a, isNot(b));
      expect(NextEpisodeMemory.keyOf('q', _episode(Duration.zero)), isNot(a));
    });

    test('answers survive a restart', () async {
      SharedPreferences.setMockInitialValues({
        'home_next_episode_v1': '{"k":[true,2,5],"x":[false,null,null]}',
      });
      final memory = NextEpisodeMemory.instance;
      await memory.load();
      expect(memory['k']?.exists, isTrue);
      expect(memory['k']?.season, 2);
      expect(memory['k']?.number, 5);
      expect(memory['x']?.exists, isFalse);
    });
  });
}
