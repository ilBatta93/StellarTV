import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/title_display.dart';
import 'package:stellar_tv/services/playback_progress_writer.dart';
import 'package:stellar_tv/services/tmdb_service.dart';
import 'package:stellar_tv/models/history_entry.dart';
import 'package:stellar_tv/models/content_type.dart';

void main() {
  test(
    'Metadata dates and technical suffixes are removed without losing real numbers',
    () {
      expect(
        displayTitle('IT: Spider-Man: Brand New Day (2026) [FHD]'),
        'Spider-Man: Brand New Day',
      );
      expect(displayTitle('Animals - 2025 HEVC'), 'Animals');
      expect(displayTitle('Matchbox 17/10/2026'), 'Matchbox');
      expect(displayTitle('1917'), '1917');
      expect(
        displayTitle('2001: Odissea nello spazio'),
        '2001: Odissea nello spazio',
      );
      expect(displayTitle('Blade Runner 2049'), 'Blade Runner 2049');
      // Unmarked numeric suffixes may be part of the title: must survive.
    },
  );
  test('Real parenthetical subtitles and sequel numbers survive', () {
    expect(
      displayTitle('Alien (Director’s Cut) [1080p]'),
      'Alien (Director’s Cut)',
    );
    expect(displayTitle('Toy Story 4'), 'Toy Story 4');
  });
  test('Official Italian logo wins over neutral and English', () {
    expect(
      TmdbService.selectTitleLogo({
        'logos': [
          {'file_path': '/en.png', 'iso_639_1': 'en', 'vote_average': 10},
          {'file_path': '/none.png', 'iso_639_1': null},
          {'file_path': '/it.png', 'iso_639_1': 'it'},
        ],
      }),
      'https://image.tmdb.org/t/p/w500/it.png',
    );
    expect(TmdbService.selectTitleLogo({'logos': []}), isNull);
  });
  test(
    'Automatic overlay completion is 100 percent and cannot be overwritten by a late save',
    () async {
      final writer = PlaybackProgressWriter();
      final waiting = Completer<void>();
      var position = 0, duration = 1200;
      final early = writer.save(() async {
        await waiting.future;
        position = 900;
      });
      final completion = writer.complete(() async {
        position = duration;
      });
      await writer.save(() async {
        position = 901;
      });
      waiting.complete();
      await early;
      await completion;
      expect(position, 1200);
      final entry = HistoryEntry(
        contentId: 'episode',
        type: ContentType.series,
        title: 'Episode',
        posterUrl: '',
        group: '',
        position: Duration(seconds: position),
        duration: Duration(seconds: duration),
        lastWatchedAt: DateTime(2026),
      );
      expect(entry.progress, 1.0);
      expect(entry.isWatched, isTrue);
      expect(entry.resumePosition, isNull);
    },
  );
  test(
    'Manual next saves partial progress without forcing completion',
    () async {
      final writer = PlaybackProgressWriter();
      var position = 0;
      await writer.save(() async {
        position = 300;
      });
      expect(position, 300);
      await writer.save(() async {
        position = 301;
      });
      expect(position, 301);
    },
  );
  test('Repeated overlay trigger completes once', () async {
    final writer = PlaybackProgressWriter();
    var calls = 0;
    await writer.complete(() async {
      calls++;
    });
    await writer.complete(() async {
      calls++;
    });
    expect(calls, 1);
  });
}
