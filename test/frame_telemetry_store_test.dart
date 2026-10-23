import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/frame_telemetry_store.dart';

void main() {
  test(
    'restart preserves previous checkpoint while new measurement writes',
    () async {
      final dir = await Directory.systemTemp.createTemp('telemetry');
      try {
        final store = FrameTelemetryStore(dir.path);
        expect(await store.recover(), isNull);
        await store.save({
          'kind': 'performance',
          'v': 2,
          'frames': 3880,
          'peakMs': 12191,
        });
        final restarted = FrameTelemetryStore(dir.path);
        final previous = await restarted.recover();
        expect(previous?['frames'], 3880);
        expect(previous?['peakMs'], 12191);
        await restarted.save({'kind': 'performance', 'v': 2, 'frames': 1});
        expect(previous?['frames'], 3880);
        expect(
          await File('${dir.path}/telemetry_previous.json').exists(),
          isTrue,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('corrupt current never deletes a valid recovered report', () async {
    final dir = await Directory.systemTemp.createTemp('telemetry');
    try {
      final store = FrameTelemetryStore(dir.path);
      await store.save({'kind': 'performance', 'v': 2, 'frames': 42});
      await FrameTelemetryStore(dir.path).recover();
      await File('${dir.path}/telemetry_current.json').writeAsString('{broken');
      expect((await FrameTelemetryStore(dir.path).recover())?['frames'], 42);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
