/// What a progress sample does while the resume point is not yet confirmed.
enum ResumeSample { skip, save, saveAndConfirm }

/// Playback past the resume point by this much confirms the seek held.
const resumeConfirmAfter = Duration(seconds: 30);

/// A sample before [pending] is the stream starting over, not the viewer's
/// progress, and never overwrites the saved point. One at [pending] is saved
/// but keeps it pending: a refused network seek can still fall back to the
/// start right after looking landed.
ResumeSample resumeSample(Duration position, Duration pending) {
  if (position < pending - const Duration(seconds: 10)) {
    return ResumeSample.skip;
  }
  return position >= pending + resumeConfirmAfter
      ? ResumeSample.saveAndConfirm
      : ResumeSample.save;
}

/// Serializes resume saves so an explicit completion cannot be overwritten
/// by a timer, lifecycle event or disposal that was already in flight.
class PlaybackProgressWriter {
  Future<void> _tail = Future<void>.value();
  bool _completed = false;

  Future<void> save(Future<void> Function() write) {
    if (_completed) return Future<void>.value();
    final next = _tail.then((_) => write());
    _tail = next.catchError((Object _) {});
    return next;
  }

  Future<void> complete(Future<void> Function() write) {
    if (_completed) return _tail;
    _completed = true;
    final next = _tail.then((_) => write());
    _tail = next.catchError((Object _) {});
    return next;
  }
}
