/// Metadata dimensions are not evidence that a frame reached the output.
/// Count only active, non-buffering intervals with positively missing frames.
class VideoHealth {
  VideoHealth({this.missingLimit = 3});

  final int missingLimit;
  int _missing = 0;

  bool check({
    required bool playing,
    required bool buffering,
    required bool audioOnly,
    required bool? frameAvailable,
  }) {
    if (!playing || buffering || audioOnly || frameAvailable != false) {
      _missing = 0;
      return false;
    }
    return ++_missing >= missingLimit;
  }
}