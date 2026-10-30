import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/frame_telemetry_service.dart';

void main() {
  test('frames over 16.6 ms count as jank and peak is kept', () {
    final s = FrameStats();
    s.add(buildUs: 4000, rasterUs: 6000, totalUs: 10000);
    s.add(buildUs: 30000, rasterUs: 50000, totalUs: 85000);
    s.add(buildUs: 5000, rasterUs: 5000, totalUs: 16667);
    expect(s.frames, 3);
    expect(s.jank, 1);
    expect(s.peakUs, 85000);
    expect(s.toJson()['peakMs'], 85.0);
  });

  test('fps never exceeds 60 and drops with slow frames', () {
    final s = FrameStats();
    s.add(buildUs: 1000, rasterUs: 1000, totalUs: 5000);
    expect(s.fps, closeTo(60, 0.01));
    s.add(buildUs: 1000, rasterUs: 1000, totalUs: 95000);
    expect(s.fps, closeTo(20, 0.01));
    s.reset();
    expect(s.frames, 0);
    expect(s.fps, 0);
  });

  test('histogram, cause split and slowest list stay bounded', () {
    final s = FrameStats();
    for (var i = 0; i < 40; i++) {
      s.add(
        buildUs: 1000,
        rasterUs: 40000 + i * 1000,
        totalUs: 50000 + i * 10000,
        context: 'home',
      );
    }
    s.add(buildUs: 120000, rasterUs: 1000, totalUs: 300000);
    expect(s.histogram.reduce((a, b) => a + b), 41);
    // Frames over 250 ms: totals 260..440 (19) plus the 300 ms frame.
    expect(s.histogram[5], 20);
    expect(s.histogram[4], 15);
    expect(s.rasterBound, 40);
    expect(s.buildBound, 1);
    expect(s.slowest.length, FrameStats.slowestKept);
    expect(s.slowest.first['ms'], 440.0);
    expect(s.peakContext, 'home');
  });

  test('event-loop stalls are bucketed and the worst ones kept', () {
    final r = ResponsivenessStats();
    r.addLag(3, 0, 'home');
    r.addLag(80, 10, 'home');
    r.addLag(300, 20, 'player diretta');
    r.addLag(1500, 30, 'player diretta');
    expect(r.lagHistogram, [1, 1, 0, 1, 1]);
    expect(r.stallsOver250, 2);
    expect(r.maxLagMs, 1500);
    expect(r.slowestLags.first['at'], 'player diretta');
    expect(r.slowestLags.length, 2);
  });

  test('slow keys add dispatch wait to time to frame', () {
    final r = ResponsivenessStats();
    r.addKey(key: 'Arrow Up', frameMs: 20, dispatchMs: 10);
    r.addKey(key: 'Select', frameMs: 90, dispatchMs: 400, context: 'player');
    r.addKey(key: 'Arrow Down', frameMs: 200);
    expect(r.keys, 3);
    expect(r.slowKeys, 2);
    expect(r.dispatchSamples, 2);
    expect(r.maxDispatchMs, 400);
    expect(r.avgKeyFrameMs, closeTo(103.3, 0.1));
    expect(r.slowestKeys.first['key'], 'Select');
    expect(r.slowestKeys.first['ms'], 490);
    expect(r.slowestKeys.last.containsKey('dispatchMs'), isFalse);
  });

  test('commands and builds stay bounded in the report', () {
    final r = ResponsivenessStats();
    r.addCommand('exo.pausa', 40);
    r.addCommand('exo.pausa', 600, 5);
    r.addCommand('exo.stato', 20);
    for (var i = 0; i < 50; i++) {
      r.addBuild('screen$i@home');
    }
    r.addBuild('diretta@player diretta');
    r.addBuild('diretta@player diretta');
    expect(r.slowestCommand?.key, 'exo.pausa');
    final json = r.toJson();
    final pause = (json['commands'] as Map)['exo.pausa'] as Map;
    expect(pause['over250'], 1);
    expect(pause['maxAt'], 5);
    final builds = json['builds'] as Map;
    expect(builds.length, 40);
    expect(builds.keys.first, 'diretta@player diretta');
    r.reset();
    expect(r.commands, isEmpty);
    expect(r.keys, 0);
  });
}
