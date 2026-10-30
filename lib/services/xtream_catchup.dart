import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/epg_program.dart';

/// Archive is provider history, not a local TS rewind buffer.
class XtreamCatchup {
  static bool _zonesReady = false;

  static bool available(Channel channel, EpgProgram programme, DateTime now) =>
      channel.type == ContentType.live &&
      channel.archiveDays > 0 &&
      programme.endTime.isAfter(programme.startTime) &&
      !programme.startTime.isAfter(now) &&
      programme.startTime.isAfter(
        now.subtract(Duration(days: channel.archiveDays)),
      );

  static String? url(
    Channel channel,
    EpgProgram programme, {
    required DateTime now,
    required String timezone,
  }) {
    if (!available(channel, programme, now)) return null;
    final source = Uri.tryParse(channel.url);
    if (source == null || source.hasQuery || source.hasFragment) return null;
    final parts = source.pathSegments;
    final live = parts.indexOf('live');
    if (live < 0 || parts.length != live + 4) return null;
    final id = parts.last.split('.').first;
    if (int.tryParse(id) == null) return null;
    if (!_zonesReady) {
      tzdata.initializeTimeZones();
      _zonesReady = true;
    }
    tz.Location location;
    try {
      location = tz.getLocation(timezone);
    } catch (_) {
      return null;
    }
    final start = tz.TZDateTime.from(programme.startTime, location);
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${start.year}-${two(start.month)}-${two(start.day)}:${two(start.hour)}-${two(start.minute)}';
    final end = programme.endTime.isBefore(now) ? programme.endTime : now;
    final minutes = (end.difference(programme.startTime).inSeconds / 60).ceil();
    if (minutes < 1) return null;
    return source
        .replace(
          pathSegments: [
            ...parts.take(live),
            'timeshift',
            parts[live + 1],
            parts[live + 2],
            '$minutes',
            stamp,
            '$id.ts',
          ],
        )
        .toString();
  }
}
