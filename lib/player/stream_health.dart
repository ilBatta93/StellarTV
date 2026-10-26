/// One health budget for the first picture and a later freeze.
///
/// Time spent buffering inside [keyframeGrace] is a slow keyframe, not a
/// failure. After that grace the same picture budget still ends a stream
/// that never draws. A freeze is counted only after frames have moved.
enum StreamHealthKind { picture, stall }

class StreamHealthDecision {
  const StreamHealthDecision(this.kind, {this.mediaAdvancing = false});
  final StreamHealthKind kind;
  final bool mediaAdvancing;
}

class StreamHealth {
  StreamHealth({
    required this.pictureBudget,
    required this.stallSamples,
    this.keyframeGrace = const Duration(seconds: 6),
    this.step = const Duration(seconds: 1),
  });

  final Duration pictureBudget;
  final int stallSamples;
  final Duration keyframeGrace;
  final Duration step;

  Duration _awaitingPicture = Duration.zero;
  Duration _keyframeWait = Duration.zero;
  int _frozen = 0;
  bool _seenMotion = false;
  int? _baseline;
  bool _pictureSettled = false;

  StreamHealthDecision? tick({
    required bool evaluatePicture,
    required bool evaluateStall,
    required bool viewerPaused,
    required bool audioOnly,
    required bool playing,
    required bool buffering,
    required bool ended,
    required bool? frameAvailable,
    required int? frames,
    required bool mediaAdvanced,
  }) {
    if (viewerPaused || audioOnly || ended || !playing) {
      _frozen = 0;
      _baseline = null;
      return null;
    }
    if (frameAvailable == true) _pictureSettled = true;

    if (evaluatePicture && !_pictureSettled && frameAvailable == false) {
      if (buffering && _keyframeWait < keyframeGrace) {
        _keyframeWait += step;
        return null;
      }
      _awaitingPicture += step;
      if (_awaitingPicture >= pictureBudget) {
        return StreamHealthDecision(
          StreamHealthKind.picture,
          mediaAdvancing: mediaAdvanced && !buffering,
        );
      }
      return null;
    }

    if (!evaluateStall) return null;
    final previous = _baseline;
    if (previous != null && frames != null && frames > previous) {
      _seenMotion = true;
    }
    final stalled = streamFrameStalled(
      viewerPaused: false,
      audioOnly: false,
      playing: true,
      buffering: buffering,
      ended: false,
      seenMotion: _seenMotion,
      frames: frames,
      baseline: previous,
    );
    if (buffering || frames == null) {
      _frozen = 0;
      _baseline = null;
      return null;
    }
    _baseline = frames;
    if (!stalled) {
      _frozen = 0;
      return null;
    }
    _frozen++;
    if (_frozen < stallSamples) return null;
    _frozen = 0;
    _baseline = null;
    return const StreamHealthDecision(StreamHealthKind.stall);
  }
}

/// True when play is active, frames were already moving, and the native
/// counter did not advance. A pause, a buffer, or an unknown counter is not
/// a stall.
bool streamFrameStalled({
  required bool viewerPaused,
  required bool audioOnly,
  required bool playing,
  required bool buffering,
  required bool ended,
  required bool seenMotion,
  required int? frames,
  required int? baseline,
}) {
  if (viewerPaused || audioOnly || !playing || buffering || ended) {
    return false;
  }
  if (!seenMotion || frames == null || baseline == null) return false;
  return frames <= baseline;
}
