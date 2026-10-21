enum TvHiddenKey { ok, up, down }

enum TvHiddenAction { none, skipIntro, outro, pauseAndControls, previousChannel, nextChannel, info, quickPanel }

/// Only used with hidden controls. Visible controls and modal focus own their keys.
TvHiddenAction tvHiddenAction(TvHiddenKey key, {
  required bool live,
  required bool repeat,
  required bool intro,
  required bool outro,
}) {
  // Held OK must never pause/resume twice; held vertical arrows must not
  // open multiple panels or queue several provider connections.
  if (repeat) return TvHiddenAction.none;
  if (key == TvHiddenKey.ok) {
    if (intro) return TvHiddenAction.skipIntro;
    if (outro) return TvHiddenAction.outro;
    return TvHiddenAction.pauseAndControls;
  }
  if (live) {
    return key == TvHiddenKey.up
        ? TvHiddenAction.previousChannel
        : TvHiddenAction.nextChannel;
  }
  return key == TvHiddenKey.up ? TvHiddenAction.info : TvHiddenAction.quickPanel;
}

Duration? remainingPlaybackTime(Duration duration, Duration position, double speed) {
  if (duration <= Duration.zero || !speed.isFinite || speed <= 0) return null;
  final remaining = duration - position;
  return remaining <= Duration.zero
      ? Duration.zero
      : Duration(microseconds: (remaining.inMicroseconds / speed).round());
}