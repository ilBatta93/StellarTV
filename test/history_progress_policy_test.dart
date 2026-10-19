import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/history_entry.dart';
import 'package:stellar_tv/models/watch_completion_policy.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

HistoryEntry entry(ContentType type, int positionMs, int durationMs) => HistoryEntry(
  contentId: 'title', type: type, title: 'Title', posterUrl: '', group: '',
  position: Duration(milliseconds: positionMs),
  duration: Duration(milliseconds: durationMs),
  lastWatchedAt: DateTime(2026, 10, 18),
  watchedPercent: 95,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Watched threshold defaults to 94 and is adjustable persistently', () async {
    final ui = UiSettings();
    await ui.load();
    expect(ui.watchedPercent, 94);
    final original = ui.signature;
    await ui.setWatchedPercent(90);
    expect(ui.signature, isNot(original));
    final reloaded = UiSettings();
    await reloaded.load();
    expect(reloaded.watchedPercent, 90);
    expect(entry(ContentType.series, 899999, 1000000).copyWith(watchedPercent: 90).isWatched, isFalse);
    expect(entry(ContentType.series, 900000, 1000000).copyWith(watchedPercent: 90).isWatched, isTrue);
    expect(entry(ContentType.movie, 999999, 1000000).copyWith(watchedPercent: 100).isWatched, isFalse);
    expect(entry(ContentType.movie, 1000000, 1000000).copyWith(watchedPercent: 100).isWatched, isTrue);
    expect(WatchCompletionPolicy.normalize(0), 94);
    expect(WatchCompletionPolicy.normalize(101), 94);
    ui.dispose(); reloaded.dispose();
  });
  test('Detail countdown applies to started movies and the selected episode only', () {
    expect(entry(ContentType.movie, 0, 7200000).startedRemainingMinutes, isNull);
    expect(entry(ContentType.movie, 5400000, 7200000).startedRemainingMinutes, 30);
    expect(entry(ContentType.series, 600000, 2400000).startedRemainingMinutes, 30);
    expect(entry(ContentType.anime, 600000, 2400000).startedRemainingMinutes, 30);
    expect(entry(ContentType.series, 600000, 0).startedRemainingMinutes, isNull);
    expect(entry(ContentType.live, 600000, 2400000).startedRemainingMinutes, isNull);
  });
  for (final type in [ContentType.movie, ContentType.series, ContentType.anime]) {
    test('$type is watched at exactly 95%, but not one millisecond earlier', () {
      const runtime = 1200000;
      final before = entry(type, 1139999, runtime);
      final complete = entry(type, 1140000, runtime);
      expect(before.isWatched, isFalse);
      expect(before.resumePosition, const Duration(milliseconds: 1139999));
      expect(complete.isWatched, isTrue);
      expect(complete.resumePosition, isNull);
      expect(complete.position, const Duration(minutes: 19));
      expect(complete.progress, 0.95);
      expect(entry(type, 1150000, runtime).isWatched, isTrue);
    });
  }
  test('Two minutes of credits do not complete a short episode below 95%', () {
    expect(entry(ContentType.series, 480000, 600000).isWatched, isFalse);
    expect(entry(ContentType.series, 570000, 600000).isWatched, isTrue);
  });
  test('Live and unknown duration never become watched', () {
    expect(entry(ContentType.live, 950000, 1000000).isWatched, isFalse);
    expect(entry(ContentType.movie, 950000, 0).isWatched, isFalse);
  });
  test('Movie minutes remaining use actual runtime and round partial minutes up', () {
    expect(entry(ContentType.movie, 5400000, 7200000).remainingMovieMinutes, 30);
    expect(entry(ContentType.movie, 7139999, 7200000).remainingMovieMinutes, 2);
    expect(entry(ContentType.movie, 7140000, 7200000).remainingMovieMinutes, 1);
    expect(entry(ContentType.movie, 7199999, 7200000).remainingMovieMinutes, 1);
    expect(entry(ContentType.movie, 7200000, 7200000).remainingMovieMinutes, 0);
    expect(entry(ContentType.movie, 7210000, 7200000).remainingMovieMinutes, 0);
    // Classification at 95% must not invent a zero-minute remaining runtime.
    expect(entry(ContentType.movie, 6840000, 7200000).remainingMovieMinutes, 6);
  });
  test('Unknown duration and episodes never invent movie minutes', () {
    expect(entry(ContentType.movie, 1000, 0).remainingMovieMinutes, isNull);
    expect(entry(ContentType.series, 1000, 60000).remainingMovieMinutes, isNull);
    expect(entry(ContentType.live, 1000, 60000).remainingMovieMinutes, isNull);
  });
}