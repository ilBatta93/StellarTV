import '../models/epg_program.dart';

/// Presentation intervals only: archive playback always receives [program].
class EpgTimelineSlot {
  final EpgProgram program;
  final DateTime start;
  final DateTime end;
  const EpgTimelineSlot(this.program, this.start, this.end);
}

String epgTimelineKey(String channel, EpgProgram p) =>
    '$channel|${p.id}|${p.startTime.millisecondsSinceEpoch}|${p.endTime.millisecondsSinceEpoch}';

double epgTimelineX(
  DateTime time,
  DateTime start,
  Duration span,
  double width,
) => (time.difference(start).inMilliseconds / span.inMilliseconds * width)
    .clamp(0.0, width)
    .toDouble();

List<EpgTimelineSlot> epgTimelineSlots(Iterable<EpgProgram> source) {
  final sorted = source.where((p) => p.endTime.isAfter(p.startTime)).toList()
    ..sort((a, b) {
      final start = a.startTime.compareTo(b.startTime);
      if (start != 0) return start;
      final end = a.endTime.compareTo(b.endTime);
      return end != 0 ? end : a.id.compareTo(b.id);
    });
  final unique = <EpgProgram>[];
  for (final p in sorted) {
    // Same-start entries cannot have separate horizontal time positions.
    // Prefer the longest entry deterministically, retaining originals elsewhere.
    if (unique.isNotEmpty && unique.last.startTime == p.startTime) {
      unique[unique.length - 1] = p;
    } else {
      unique.add(p);
    }
  }
  return [
    for (var i = 0; i < unique.length; i++)
      EpgTimelineSlot(
        unique[i],
        unique[i].startTime,
        i + 1 < unique.length &&
                unique[i + 1].startTime.isBefore(unique[i].endTime)
            ? unique[i + 1].startTime
            : unique[i].endTime,
      ),
  ];
}
