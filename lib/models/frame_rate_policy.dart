// Auto frame rate: which display refresh rate suits a video.

/// Broadcast and film rates. Containers often round them (23.98, 29.97)
/// and mpv's estimate jitters, so a measured value snaps to the nearest one.
const kStandardFrameRates = <double>[
  24000 / 1001,
  24,
  25,
  30000 / 1001,
  30,
  48000 / 1001,
  48,
  50,
  60000 / 1001,
  60,
];

/// Highest refresh the player asks for: above it the menus would draw at a
/// rate many TVs only reach in game modes.
const kMaxMatchedRefresh = 60.5;

/// Nearest standard rate within 1%, or null when [fps] is unknown or odd.
double? snapFrameRate(double? fps) {
  if (fps == null || !fps.isFinite || fps < 10 || fps > 121) return null;
  double? best;
  var bestDiff = double.infinity;
  for (final rate in kStandardFrameRates) {
    final diff = (fps - rate).abs() / rate;
    if (diff < bestDiff) {
      bestDiff = diff;
      best = rate;
    }
  }
  if (bestDiff <= 0.01) return best;
  // 100 and 120 fps are rare but real: they still map to 50 and 60 Hz
  // displays through the exact multiple below.
  final doubled = snapFrameRate(fps / 2);
  return doubled == null ? null : doubled * 2;
}

/// Cadences a count of drawn pictures can tell apart. A few seconds of
/// counting cannot separate 24 from 25 (a 25 fps channel was counted at 24
/// and played at 24 Hz), so 24 is left out: only live streams are counted,
/// and films declare their own rate.
const kMeasuredFrameRates = <double>[25, 30, 50, 60];

/// Nearest cadence within 6% for a rate measured by counting pictures, or
/// null when the count fits none (a stalled or dropping decoder).
double? snapMeasuredFrameRate(double? fps) {
  if (fps == null || !fps.isFinite || fps <= 0) return null;
  double? best;
  var bestDiff = double.infinity;
  for (final rate in kMeasuredFrameRates) {
    final diff = (fps - rate).abs() / rate;
    if (diff < bestDiff) {
      bestDiff = diff;
      best = rate;
    }
  }
  return bestDiff <= 0.06 ? best : null;
}

/// Display rate for [fps] among [rates]: the highest exact multiple not above
/// [kMaxMatchedRefresh], so 25 fps plays at 50 Hz and the menus stay fluid.
/// Only video faster than that limit (100 fps) may use a fraction (50 Hz).
/// Null when nothing matches: the display then keeps its current mode.
double? pickRefreshRate(double? fps, Iterable<double> rates) {
  final source = snapFrameRate(fps);
  if (source == null) return null;
  double? best;
  for (final rate in rates) {
    if (rate > kMaxMatchedRefresh) continue;
    if (rate < source && source <= kMaxMatchedRefresh) continue;
    final ratio = rate >= source ? rate / source : source / rate;
    final whole = ratio.roundToDouble();
    // 0.05% separates 23.976 from 24 and 59.94 from 60.
    if (whole < 1 || (ratio - whole).abs() / whole > 0.0005) continue;
    if (best == null || rate > best) best = rate;
  }
  return best;
}

/// "50 Hz", "59,94 Hz", "23,976 Hz": the decimals a TV menu would show.
String formatRefreshRate(double hz) => '${_trimmed(hz)} Hz';

/// "25 fps", "23,976 fps".
String formatFrameRate(double fps) =>
    '${_trimmed(snapFrameRate(fps) ?? fps)} fps';

String _trimmed(double value) {
  final rounded = value.roundToDouble();
  if ((value - rounded).abs() < 0.005) return rounded.toInt().toString();
  var text = value.toStringAsFixed(3);
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  return text.replaceAll('.', ',');
}
