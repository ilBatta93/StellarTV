import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/epg_program.dart';
import 'package:stellar_tv/services/epg_timeline.dart';

import 'epg_channel_match_test.dart' as channel_match;

void main() {
  channel_match.main();
  final base = DateTime.utc(2026, 10, 23, 8);
  EpgProgram p(String id, int start, int end) => EpgProgram(
    id: id,
    channelId: 'c',
    title: id,
    description: '',
    startTime: base.add(Duration(minutes: start)),
    endTime: base.add(Duration(minutes: end)),
  );
  test('overlap clips presentation only and retains archive timestamps', () {
    final original = p('a', 0, 60);
    final slots = epgTimelineSlots([p('b', 30, 90), original]);
    expect(slots[0].end, base.add(const Duration(minutes: 30)));
    expect(identical(slots[0].program, original), isTrue);
    expect(original.endTime, base.add(const Duration(minutes: 60)));
    expect(slots[0].end, slots[1].start);
  });
  test(
    'duplicate starts have one deterministic position and stable identity',
    () {
      final a = p('short', 0, 5), b = p('long', 0, 30);
      final slots = epgTimelineSlots([b, a]);
      expect(slots.length, 1);
      expect(identical(slots.single.program, b), isTrue);
      expect(epgTimelineKey('c', a), isNot(epgTimelineKey('c', b)));
    },
  );
  test('invalid intervals omitted and nested entries never overlap', () {
    final slots = epgTimelineSlots([
      p('a', 0, 90),
      p('b', 10, 20),
      p('c', 20, 30),
      p('invalid', 40, 40),
    ]);
    expect(slots.length, 3);
    for (var i = 0; i < slots.length; i++) {
      expect(slots[i].end.isAfter(slots[i].start), isTrue);
      if (i > 0) expect(slots[i].start.isBefore(slots[i - 1].end), isFalse);
    }
  });
  test('window clipping and short interval geometry are exact', () {
    const span = Duration(hours: 2);
    expect(
      epgTimelineX(base.subtract(const Duration(minutes: 1)), base, span, 600),
      0,
    );
    expect(
      epgTimelineX(base.add(const Duration(hours: 3)), base, span, 600),
      600,
    );
    expect(
      epgTimelineX(base.add(const Duration(hours: 1)), base, span, 600),
      300,
    );
    expect(
      epgTimelineX(base.add(const Duration(seconds: 12)), base, span, 600),
      1,
    );
  });
}
