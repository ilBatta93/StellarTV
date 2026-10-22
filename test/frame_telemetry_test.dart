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
}
