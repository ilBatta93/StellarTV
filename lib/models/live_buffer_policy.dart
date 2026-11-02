/// Live rewind budget, the real rewind window, and adaptive forward
/// buffering. Pure policy: device facts and engine readings come in, sizes
/// and decisions come out.
library;

const int _mib = 1024 * 1024;

/// Bytes the player may keep behind the playback point for live rewind.
///
/// A share of the device RAM, bounded per device class: TV sticks with 1-2 GB
/// keep a small window, phones and tablets a wider one. A device that
/// declares itself low on RAM keeps only a short pause buffer. While the
/// viewer pauses, the forward buffer may grow to the same size, so the
/// paused minutes stay rewindable without ever exceeding twice this budget.
int liveRewindBytes({
  required bool tv,
  required int? totalRamBytes,
  required bool lowRam,
}) {
  if (lowRam) return 24 * _mib;
  final ram = totalRamBytes;
  if (ram == null || ram <= 0) return tv ? 48 * _mib : 128 * _mib;
  final share = (ram * (tv ? 0.05 : 0.07)).round();
  final floor = tv ? 32 * _mib : 64 * _mib;
  final cap = tv ? 192 * _mib : 384 * _mib;
  if (share < floor) return floor;
  if (share > cap) return cap;
  return share;
}

/// One cached range the player can seek in, in stream time.
class SeekRange {
  const SeekRange(this.start, this.end);
  final Duration start;
  final Duration end;
}

/// The real live window around [position], read from the player's cache.
class LiveWindow {
  const LiveWindow({required this.start, required this.edge});

  /// Oldest point the viewer can rewind to.
  final Duration start;

  /// Newest buffered point: the live picture.
  final Duration edge;

  Duration rewindable(Duration position) {
    final d = position - start;
    return d.isNegative ? Duration.zero : d;
  }

  Duration behind(Duration position) {
    final d = edge - position;
    return d.isNegative ? Duration.zero : d;
  }

  /// [target] kept inside the window, a little short of the edge so a jump
  /// to the live picture never lands past the buffered data.
  Duration clamp(
    Duration target, {
    Duration margin = const Duration(seconds: 1),
  }) {
    final last = edge - margin > start ? edge - margin : start;
    if (target < start) return start;
    if (target > last) return last;
    return target;
  }
}

/// The fields of mpv's `demuxer-cache-state` used here.
class CacheState {
  const CacheState({required this.ranges, required this.underrun});
  final List<SeekRange> ranges;

  /// The decoder asked for a packet the network had not delivered yet.
  final bool underrun;

  /// Null when [decoded] is not the expected map.
  static CacheState? parse(Object? decoded) {
    if (decoded is! Map) return null;
    Duration? seconds(Object? v) => v is num && v.isFinite
        ? Duration(microseconds: (v * 1000000).round())
        : null;
    final ranges = <SeekRange>[];
    final raw = decoded['seekable-ranges'];
    if (raw is List) {
      for (final r in raw) {
        if (r is! Map) continue;
        final start = seconds(r['start']);
        final end = seconds(r['end']);
        if (start != null && end != null) ranges.add(SeekRange(start, end));
      }
    }
    return CacheState(ranges: ranges, underrun: decoded['underrun'] == true);
  }
}

/// Picks the range holding [position]. A range that does not contain the
/// playback point is old data from before a timestamp reset and is ignored.
/// [tolerance] covers the decoder reading slightly ahead of the cache start.
LiveWindow? liveWindowAt(
  Duration position,
  List<SeekRange> ranges, {
  Duration tolerance = const Duration(seconds: 2),
}) {
  for (final r in ranges) {
    if (r.end <= r.start) continue;
    if (position >= r.start - tolerance && position <= r.end + tolerance) {
      return LiveWindow(start: r.start, edge: r.end);
    }
  }
  return null;
}

/// True when the stream clock moved in a way no seek explains: a backward
/// jump of the playback point, or a playback point far outside every range.
/// Broadcast MPEG-TS resets its timestamps on a provider restart; keeping
/// the old cache then replays already-seen minutes.
bool liveClockJumped({
  required Duration previous,
  required Duration current,
  required bool seeking,
  Duration backwardLimit = const Duration(seconds: 3),
}) {
  if (seeking) return false;
  return previous - current > backwardLimit;
}

/// Raises the forward buffer after repeated stalls and lowers it again after
/// a long calm stretch. One stall can be noise; two within [stallWindow]
/// step up one level.
class AdaptiveBuffer {
  AdaptiveBuffer({int level = 0}) : _level = level.clamp(0, maxLevel);

  static const int maxLevel = 3;
  static const Duration stallWindow = Duration(minutes: 2);
  static const Duration calmToRelax = Duration(minutes: 10);

  int _level;
  int get level => _level;
  final List<DateTime> _stalls = [];
  DateTime? _calmSince;

  /// A stall after the picture was already moving. True when the level rose.
  bool onStall(DateTime now) {
    _calmSince = now;
    _stalls
      ..removeWhere((t) => now.difference(t) > stallWindow)
      ..add(now);
    if (_stalls.length < 2 || _level >= maxLevel) return false;
    _level++;
    _stalls.clear();
    return true;
  }

  /// Called while playback runs without stalls. True when the level fell.
  bool onSteady(DateTime now) {
    final since = _calmSince ??= now;
    if (_level == 0 || now.difference(since) < calmToRelax) return false;
    _level--;
    _calmSince = now;
    return true;
  }
}

/// Seconds mpv refills after an underrun before playing again, or null to
/// keep playing through it.
///
/// Live data arrives in real time: the only cushion against a jittery
/// server is playing a few seconds behind the newest data. Level 0 keeps
/// the live edge (no pause, as before); each level makes the next underrun
/// refill a deeper cushion, which then stays. With the rewind buffer active
/// those seconds are simply part of the window.
double? mpvCachePauseWait({required int level, required bool live}) {
  final l = level.clamp(0, AdaptiveBuffer.maxLevel);
  if (live) return const [null, 2.0, 4.0, 6.0][l];
  return const [1.0, 3.0, 5.0, 8.0][l];
}

/// Film/series prefetch in seconds for a buffer [level], still bounded by
/// the forward cache bytes.
int mpvCacheSeconds(int level) =>
    const [30, 45, 60, 90][level.clamp(0, AdaptiveBuffer.maxLevel)];
