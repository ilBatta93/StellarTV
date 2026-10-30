import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/live_diagnostics_log.dart';
import 'package:stellar_tv/services/live_diagnostics_tracker.dart';

void main() {
  test('diagnostics is off by default and stops recording when disabled', () {
    final log = LiveDiagnosticsLog();
    log.add('attempt');
    expect(log.events, isEmpty);
    log.enabled = true;
    log.add('attempt');
    log.enabled = false;
    log.add('error');
    expect(log.events.length, 1);
  });
  test('reports are bounded to the newest 1000 events', () {
    final log = LiveDiagnosticsLog()..enabled = true;
    for (var i = 0; i < 1100; i++) {
      log.add('attempt', data: {'index': i});
    }
    expect(log.events.length, 1000);
    expect(log.events.first['index'], 100);
  });
  test('URL credentials and native error strings never enter reports', () {
    const url =
        'https://provider.example/live/secretUser/secretPassword/123.ts?token=secretToken';
    final log = LiveDiagnosticsLog(salt: 'private-salt')..enabled = true;
    log.add(
      'error',
      data: {
        'stream': log.streamId(url),
        'category': LiveDiagnosticsLog.errorKind('HTTP 403 $url'),
      },
    );
    final report = log.report({'platform': 'android'});
    expect(report, contains('http_403'));
    expect(report, isNot(contains('secretUser')));
    expect(report, isNot(contains('secretPassword')));
    expect(report, isNot(contains('secretToken')));
    expect(log.streamId(url), log.streamId(url));
    expect(
      log.streamId(url),
      isNot(LiveDiagnosticsLog(salt: 'other').streamId(url)),
    );
  });
  test('engine state keeps numbers and codec names, never other text', () {
    final data = engineStateData(
      playing: true,
      buffering: false,
      positionMs: 314,
      audioOnly: false,
      firstFrame: true,
      size: const Size(1920, 1080),
      renderedFrames: null,
      metrics: {
        'frameDropCount': '12',
        'estimatedFps': '24.9',
        'cacheSeconds': 'nan',
        'videoCodec': 'h264',
        'hwdecCurrent': 'https://host.example/x',
        'cacheKib': 'abc',
      },
    );
    final log = LiveDiagnosticsLog()..enabled = true;
    log.add('engine_state', data: data);
    final report = log.report({'platform': 'android'});
    expect(report, contains('"frameDropCount": 12'));
    expect(report, contains('"estimatedFps": 24.9'));
    expect(report, contains('"videoCodec": "h264"'));
    expect(report, contains('"videoWidth": 1920'));
    expect(report, contains('"engine_state"'));
    expect(report, isNot(contains('host.example')));
    expect(report, isNot(contains('cacheSeconds')));
    expect(report, isNot(contains('cacheKib')));
  });
  test('stationary clock is one suspected stall after 5s, never during pause or buffering', () {
    final probe = LiveStallProbe();
    bool check(int seconds, {bool playing = true, bool buffering = false}) =>
        probe.check(
          elapsed: Duration(seconds: seconds),
          position: const Duration(seconds: 10),
          playing: playing,
          buffering: buffering,
        );
    expect(check(0), false);
    expect(check(4), false);
    expect(check(5), true);
    expect(check(8), false);
    expect(check(15, playing: false), false);
    expect(check(25, buffering: true), false);
    expect(check(26), false);
    expect(check(29), false);
  });
}
