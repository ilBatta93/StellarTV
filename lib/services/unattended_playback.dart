/// Counts episodes started by autoplay while nobody touches the remote, so a
/// viewer who falls asleep is not carried through a whole season: after
/// [maxAutoAdvances] episodes playback stops at the end of the current one,
/// which is then complete and Home offers the following episode.
class UnattendedPlayback {
  static const maxAutoAdvances = 3;

  static int _advances = 0;
  static bool _autoOpening = false;

  static bool get mayAdvance => _advances < maxAutoAdvances;

  /// Any key, tap or manual "next" restarts the count.
  static void userActed() => _advances = 0;

  /// Called right before autoplay opens the next episode.
  static void autoAdvanced() {
    _advances++;
    _autoOpening = true;
  }

  /// A player page opened by the viewer, not by autoplay, starts afresh.
  static void playerOpened() {
    if (!_autoOpening) _advances = 0;
    _autoOpening = false;
  }
}
