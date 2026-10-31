import 'dart:async';

/// Lets a long loop on the UI isolate yield to the event loop about every
/// [budget], so frames and remote keys are served between slices.
class WorkSlicer {
  WorkSlicer({this.budget = const Duration(milliseconds: 8)});

  final Duration budget;
  final _clock = Stopwatch()..start();
  int _count = 0;

  /// Call once per item; awaits only when the budget is spent.
  FutureOr<void> pause() {
    if (++_count % 64 != 0 || _clock.elapsed < budget) return null;
    return Future<void>.delayed(Duration.zero).then((_) => _clock.reset());
  }
}
