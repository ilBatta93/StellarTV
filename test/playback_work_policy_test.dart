import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:stellar_tv/services/foreground_policy.dart';
import 'package:stellar_tv/services/playback_work_policy.dart';

void main() {
  test('guide waits for close even when video is paused', () {
    final p = PlaybackWorkPolicy();
    final session = Object();
    p.update(session, cloudBlocked: true);
    expect(p.blocksGuide, true);
    p.update(session, cloudBlocked: false);
    expect(p.blocksGuide, true);
    p.remove(session);
    expect(p.blocksGuide, false);
  });
  test('cloud waits for explicit pause and resumes its gate on play', () {
    final p = PlaybackWorkPolicy();
    final session = Object();
    p.update(session, cloudBlocked: true);
    expect(p.blocksCloud, true);
    p.update(session, cloudBlocked: false);
    expect(p.blocksCloud, false);
    p.update(session, cloudBlocked: true);
    expect(p.blocksCloud, true);
  });
  test('ending one MultiView session does not release another', () {
    final p = PlaybackWorkPolicy();
    final a = Object(), b = Object();
    p.update(a, cloudBlocked: true);
    p.update(b, cloudBlocked: true);
    p.remove(a);
    expect(p.blocksCloud, true);
    expect(p.blocksGuide, true);
    p.remove(b);
    expect(p.blocksCloud, false);
    expect(p.blocksGuide, false);
  });
  test('listeners run only on state transitions and can unsubscribe', () {
    final p = PlaybackWorkPolicy();
    final session = Object();
    var calls = 0;
    void listener() => calls++;
    p.addListener(listener);
    p.update(session, cloudBlocked: true);
    p.update(session, cloudBlocked: true);
    expect(calls, 1);
    p.removeListener(listener);
    p.remove(session);
    expect(calls, 1);
  });
  test('catalog copies wait for a closed session and a visible app', () {
    final p = PlaybackWorkPolicy();
    final session = Object();
    expect(p.blocksCatalogWrite, false);
    p.update(session, cloudBlocked: false);
    expect(p.hasPlayback, true);
    expect(p.blocksCatalogWrite, true);
    p.remove(session);
    expect(p.blocksCatalogWrite, false);
    ForegroundPolicy.instance.setResumed(false);
    try {
      expect(p.blocksCatalogWrite, true);
    } finally {
      ForegroundPolicy.instance.setResumed(true);
    }
    expect(p.blocksCatalogWrite, false);
  });
  test('conflict retry jitter stays within 250–400 milliseconds', () {
    expect(
      PlaybackWorkPolicy.conflictDelay(BoundaryRandom(0)).inMilliseconds,
      250,
    );
    expect(
      PlaybackWorkPolicy.conflictDelay(BoundaryRandom(150)).inMilliseconds,
      400,
    );
    final random = Random(1);
    for (var i = 0; i < 1000; i++) {
      final delay = PlaybackWorkPolicy.conflictDelay(random).inMilliseconds;
      expect(delay, inInclusiveRange(250, 400));
    }
  });
}

class BoundaryRandom implements Random {
  BoundaryRandom(this.value);
  final int value;
  @override
  int nextInt(int max) => value;
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
}
