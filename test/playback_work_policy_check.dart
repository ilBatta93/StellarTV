import 'dart:math';

import '../lib/services/playback_work_policy.dart';

void check(bool value, String rule) {
  if (!value) throw StateError(rule);
  print('PASS: $rule');
}

void main() {
  final p = PlaybackWorkPolicy();
  final a = Object(), b = Object();
  var calls = 0;
  void listener() => calls++;
  p.addListener(listener);
  p.update(a, cloudBlocked: true);
  check(p.blocksCloud && p.blocksGuide, 'opening blocks cloud and guide');
  p.update(a, cloudBlocked: true);
  check(calls == 1, 'stable state does not notify again');
  p.update(a, cloudBlocked: false);
  check(!p.blocksCloud && p.blocksGuide, 'pause releases cloud only');
  p.update(a, cloudBlocked: true);
  p.update(b, cloudBlocked: true);
  p.remove(a);
  check(
    p.blocksCloud && p.blocksGuide,
    'one closed MultiView tile cannot release another',
  );
  p.remove(b);
  check(!p.blocksCloud && !p.blocksGuide, 'last close releases work');
  p.removeListener(listener);
  final before = calls;
  p.update(a, cloudBlocked: true);
  check(calls == before, 'disposed listener is not called');
  p.remove(a);
  final random = Random(7);
  final delays = List.generate(
    10000,
    (_) => PlaybackWorkPolicy.conflictDelay(random).inMilliseconds,
  );
  check(
    delays.reduce(min) == 250 && delays.reduce(max) == 400,
    'conflict jitter has exact 250 and 400 ms bounds',
  );
}
