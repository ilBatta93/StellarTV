import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/services/history_episode_label.dart';

void main() {
  test('Recent series use real structured season and episode', () {
    expect(historyEpisodeLabel(type: ContentType.series, season: 2, episode: 7,
      historyTitle: 'Silo', channelTitle: 'Silo'), 'S2 · E7');
  });
  test('Restored episodes recover explicit numbers from the history title', () {
    expect(historyEpisodeLabel(type: ContentType.series,
      historyTitle: 'ITA: Silo S01E03 FHD', channelTitle: 'Silo'), 'S1 · E3');
    expect(historyEpisodeLabel(type: ContentType.anime,
      historyTitle: 'Evangelion 1x12', channelTitle: 'Evangelion'), 'S1 · E12');
  });
  test('Recent movies never get invented season or episode numbers', () {
    expect(historyEpisodeLabel(type: ContentType.movie, season: 1, episode: 2,
      historyTitle: 'Film S01E02', channelTitle: 'Film'), isNull);
  });
  test('Unknown and invalid episode numbers remain absent', () {
    expect(historyEpisodeLabel(type: ContentType.series,
      historyTitle: 'Silo 2023', channelTitle: 'Silo'), isNull);
    expect(historyEpisodeLabel(type: ContentType.series, season: 1, episode: 0,
      historyTitle: 'Silo', channelTitle: 'Silo'), isNull);
  });
}