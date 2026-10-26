import '../models/epg_data.dart';
import '../models/epg_program.dart';

/// Grid past the diretta can scroll, and the span drawn at once.
const epgGuidePast = Duration(hours: 6);
const epgGuideSpan = Duration(hours: 2);
const epgGuideFuture = Duration(hours: 36);

/// Highest "+N" the matcher can attach to a base guide.
const epgMaxTimeshift = Duration(hours: 9);

/// Synopsis kept for a cell. The programme sheet shows at most four lines.
const epgDescriptionLimit = 480;

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

DateTime epgHalfHourFloor(DateTime time) => DateTime(
  time.year,
  time.month,
  time.day,
  time.hour,
  time.minute < 30 ? 0 : 30,
);

/// Left edge of the guide the diretta can scroll back to.
DateTime epgGridOrigin(DateTime now) =>
    epgHalfHourFloor(now.subtract(epgGuidePast));

/// Left edge of the two-hour strip shown when the guide opens.
DateTime epgViewportStart(DateTime now) =>
    epgHalfHourFloor(now.subtract(const Duration(minutes: 30)));

String epgClipDescription(String value) {
  if (value.length <= epgDescriptionLimit) return value;
  var end = epgDescriptionLimit;
  final unit = value.codeUnitAt(end - 1);
  if (unit >= 0xD800 && unit <= 0xDBFF) end--;
  return value.substring(0, end);
}

bool _spans(EpgProgram program, DateTime from, DateTime to) =>
    program.endTime.isAfter(program.startTime) &&
    program.endTime.isAfter(from) &&
    program.startTime.isBefore(to);

/// Drops programmes that end before the first one crossing [from], keeping
/// any later entry that still clips a programme inside the window.
List<EpgProgram> epgSliceGuide(
  List<EpgProgram> source,
  DateTime from,
  DateTime to,
) {
  DateTime? anchor;
  for (final program in source) {
    if (!_spans(program, from, to)) continue;
    if (anchor == null || program.startTime.isBefore(anchor)) {
      anchor = program.startTime;
    }
  }
  if (anchor == null) return const [];
  var same = true;
  final kept = <EpgProgram>[];
  for (final program in source) {
    if (program.endTime.isAfter(program.startTime) &&
        program.endTime.isAfter(anchor) &&
        program.startTime.isBefore(to)) {
      kept.add(program);
    } else {
      same = false;
    }
  }
  if (same && kept.length == source.length) return source;
  return List.unmodifiable(kept);
}

/// Resident guide: the grid horizon plus the timeshift margin.
/// Programmes outside that horizon are dropped. Descriptions are clipped to
/// a cell; the overflow is not kept. Timestamps stay the archive instants.
/// A description already clipped is left as-is, so a later pass cannot
/// restore text that was discarded.
EpgData epgDataInGuideWindow(EpgData data, DateTime now) {
  final retainFrom = epgGridOrigin(now).subtract(epgMaxTimeshift);
  final retainTo = now.add(epgGuideFuture);
  final visibleFrom = epgViewportStart(now);
  final visibleTo = visibleFrom.add(epgGuideSpan);
  final programmes = <String, List<EpgProgram>>{};
  var changed = false;
  data.programmes.forEach((id, list) {
    final next = _residentChannel(
      list,
      retainFrom,
      retainTo,
      visibleFrom.subtract(epgMaxTimeshift),
      visibleTo,
    );
    if (identical(next, list)) {
      if (next.isNotEmpty) programmes[id] = next;
      return;
    }
    changed = true;
    if (next.isNotEmpty) programmes[id] = next;
  });
  if (!changed && programmes.length == data.programmes.length) return data;
  return EpgData(
    programmes: programmes,
    displayNames: data.displayNames,
    fetchedAt: data.fetchedAt,
    degraded: data.degraded,
  );
}

List<EpgProgram> _residentChannel(
  List<EpgProgram> source,
  DateTime retainFrom,
  DateTime retainTo,
  DateTime describeFrom,
  DateTime describeTo,
) {
  final sliced = epgSliceGuide(source, retainFrom, retainTo);
  var same = identical(sliced, source);
  final kept = <EpgProgram>[];
  for (final program in sliced) {
    final description = _residentDescription(program, describeFrom, describeTo);
    if (identical(description, program.description)) {
      kept.add(program);
    } else {
      same = false;
      kept.add(
        EpgProgram(
          id: program.id,
          channelId: program.channelId,
          title: program.title,
          description: description,
          startTime: program.startTime,
          endTime: program.endTime,
        ),
      );
    }
  }
  if (same) return source;
  return List.unmodifiable(kept);
}

/// Long text outside the open strip is dropped. Short text stays, so the
/// programme sheet keeps a normal synopsis. Text already within the cell
/// limit is never rewritten.
String _residentDescription(
  EpgProgram program,
  DateTime describeFrom,
  DateTime describeTo,
) {
  final raw = program.description;
  if (raw.length <= epgDescriptionLimit) return raw;
  if (!_spans(program, describeFrom, describeTo)) return '';
  return epgClipDescription(raw);
}
