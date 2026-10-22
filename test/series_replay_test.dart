import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/history_entry.dart';
import 'package:stellar_tv/models/series_details.dart';
import 'package:stellar_tv/providers/history_provider.dart';
import 'package:stellar_tv/services/series_resume_policy.dart';

void main() {
  final episodes = List.generate(20, (i) => SeriesEpisode(
    channel: Channel(id: 'e${i + 1}', name: 'Episode', url: '', logo: '', group: '', type: ContentType.series),
    season: 1, number: i + 1, title: 'Episode',
  ));
  HistoryEntry view(int number, int seconds, int day, {bool? manual}) => HistoryEntry(
    contentId: 'e$number', type: ContentType.series, title: 'Episode',
    posterUrl: '', group: '', seriesKey: 'collection',
    position: Duration(seconds: seconds), duration: const Duration(seconds: 1000),
    lastWatchedAt: DateTime(2026, 10, day), manualWatched: manual,
  );
  final completed = List.generate(20, (i) => view(i + 1, 1000, 1));
  test('Replaying episode six brings that episode back without clearing seven through twenty', () {
    final replay = view(6, 400, 22, manual: true);
    final entries = [for (final e in completed) if (e.contentId != 'e6') e, replay];
    expect(HistoryProvider.onePerSeries(entries).single.contentId, 'e6');
    expect(latestSeriesReplay(episodes, entries)?.number, 6);
    expect(replayEpisodeComplete(replay), isFalse);
    expect(entries.where((e) => e.contentId != 'e6').every((e) => e.isWatched), isTrue);
    expect(completed[5].position.inSeconds, 1000);
  });
  test('After six completes, seven is next even though seven through twenty remain watched', () {
    final entries = [...completed, view(6, 1000, 22)];
    expect(latestSeriesReplay(episodes, entries)?.number, 7);
    expect(nextEpisodeInSequence(episodes, 'e7')?.number, 8);
    expect(completed.skip(6).every((e) => e.isWatched), isTrue);
  });
  test('Completing the final episode has no following episode', () {
    expect(latestSeriesReplay(episodes, [...completed, view(20, 1000, 22)]), isNull);
    expect(latestSeriesReplay(episodes, [...completed, view(20, 400, 22)])?.number, 20);
  });
  test('An end-of-sequence cache answer never applies to a newer replay or another profile', () {
    final old = view(20, 1000, 1);
    final cache = {seriesReplayKey('a', old): false};
    expect(cache[seriesReplayKey('a', old)], isFalse);
    expect(cache[seriesReplayKey('a', view(20, 400, 22))], isNull);
    expect(cache[seriesReplayKey('b', old)], isNull);
  });
  test('Season boundary keeps the immediate next episode and unknown position stays unknown', () {
    final seasonTwo = SeriesEpisode(channel: episodes.last.channel.copyWith(id: 's2e1'), season: 2, number: 1, title: 'Episode');
    expect(nextEpisodeInSequence([...episodes, seasonTwo], 'e20')?.channel.id, 's2e1');
    expect(nextEpisodeInSequence(episodes, 'changed-id', season: 1, number: 6)?.number, 7);
    expect(() => nextEpisodeInSequence(episodes, 'missing'), throwsStateError);
  });
}