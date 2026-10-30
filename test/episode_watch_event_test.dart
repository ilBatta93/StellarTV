import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/episode_watch_event.dart';
import 'package:stellar_tv/models/history_entry.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/diagnostic_guide.dart';

void main() {
  final at = DateTime.utc(2026, 10, 21);
  test('manual completion roundtrips without any playback position', () {
    final seen = EpisodeWatchEvent('ep3', 1, at);
    final restored = EpisodeWatchEvent.parse(
      jsonDecode(jsonEncode(seen.toJson())),
    );
    expect(restored?.watched, true);
    expect(restored?.target, 'ep3');
    expect(seen.toJson().containsKey('dur'), false);
  });
  test(
    'manual state reversals and automatic reset have increasing timestamps',
    () {
      final seen = EpisodeWatchEvent('ep3', 1, at);
      final unseen = EpisodeWatchEvent(
        'ep3',
        0,
        at.add(const Duration(microseconds: 1)),
      );
      final reset = EpisodeWatchEvent(
        'ep3',
        3,
        at.add(const Duration(microseconds: 2)),
      );
      expect(unseen.newerThan(seen), true);
      expect(unseen.watched, false);
      expect(reset.newerThan(unseen), true);
      expect(reset.watched, null);
    },
  );
  test('equal timestamp conflict uses deterministic false preference', () {
    expect(
      EpisodeWatchEvent(
        'ep3',
        0,
        at,
      ).newerThan(EpisodeWatchEvent('ep3', 1, at)),
      true,
    );
    expect(
      EpisodeWatchEvent(
        'ep3',
        1,
        at,
      ).newerThan(EpisodeWatchEvent('ep3', 0, at)),
      false,
    );
  });
  test('dismissal is separate from episode completion and reversible', () {
    final dismissal = EpisodeWatchEvent('series3', 2, at, suggestion: true);
    final reset = EpisodeWatchEvent(
      'series3',
      3,
      at.add(const Duration(seconds: 1)),
      suggestion: true,
    );
    expect(EpisodeWatchEvent.parse(dismissal.toJson())?.suggestion, true);
    expect(reset.newerThan(dismissal), true);
    expect(dismissal.watched, null);
  });
  test('invalid control records fail closed', () {
    final seen = EpisodeWatchEvent('ep3', 1, at);
    expect(EpisodeWatchEvent.parse({...seen.toJson(), 'id': 'wrong'}), null);
    expect(EpisodeWatchEvent.parse({...seen.toJson(), 'pos': 5}), null);
  });
  test(
    'manual completion never changes resume, minutes or actual percentage',
    () {
      final entry = HistoryEntry(
        contentId: 'ep3',
        type: ContentType.series,
        title: 'Episode',
        posterUrl: '',
        group: '',
        position: const Duration(minutes: 10),
        duration: const Duration(minutes: 40),
        lastWatchedAt: at,
        manualWatched: true,
      );
      expect(entry.isWatched, true);
      expect(entry.isAutomaticallyWatched, false);
      expect(entry.resumePosition, const Duration(minutes: 10));
      expect(entry.remainingMinutes, 30);
      expect(entry.progress, .25);
    },
  );
  test('guided diagnostic is opt-in and preserves original evidence', () {
    const report = '{"events":[{"droppedFrames":3}]}';
    expect(guidedDiagnosticReport(report, null), report);
    final guided = jsonDecode(
      guidedDiagnosticReport(report, DiagnosticProblem.stutter),
    );
    expect(guided['report'], jsonDecode(report));
    expect(guided['guide'], {'v': 1, 'problem': 'stutter'});
  });
}
