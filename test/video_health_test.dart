import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/player/video_health.dart';

void main() {
  test('three active missing-frame checks trigger recovery, not metadata', () {
    final health = VideoHealth();
    bool missing() => health.check(playing: true, buffering: false,
        audioOnly: false, frameAvailable: false);
    expect(missing(), isFalse);
    expect(missing(), isFalse);
    expect(missing(), isTrue);
  });
  test('buffering, pause, radio and unknown signals reset failure budget', () {
    for (final reset in [
      (false, false, false, false),
      (true, true, false, false),
      (true, false, true, false),
      (true, false, false, null),
      (true, false, false, true),
    ]) {
      final health = VideoHealth(missingLimit: 2);
      expect(health.check(playing: true, buffering: false,
          audioOnly: false, frameAvailable: false), isFalse);
      expect(health.check(playing: reset.$1, buffering: reset.$2,
          audioOnly: reset.$3, frameAvailable: reset.$4), isFalse);
      expect(health.check(playing: true, buffering: false,
          audioOnly: false, frameAvailable: false), isFalse);
    }
  });
}