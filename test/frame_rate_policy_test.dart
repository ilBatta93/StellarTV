import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/frame_rate_policy.dart';

void main() {
  // Modes a Chromecast with Google TV offers at 1080p.
  const chromecast = <double>[
    23.976025,
    24.000002,
    25.0,
    29.97003,
    30.000002,
    50.0,
    59.94006,
    60.000004,
  ];

  group('snapFrameRate', () {
    test('snaps rounded and jittery values to broadcast rates', () {
      expect(snapFrameRate(23.98), closeTo(23.976, 0.001));
      expect(snapFrameRate(24.0), 24);
      expect(snapFrameRate(25.03), 25);
      expect(snapFrameRate(29.97), closeTo(29.970, 0.001));
      expect(snapFrameRate(59.94), closeTo(59.940, 0.001));
      expect(snapFrameRate(100), 100);
    });

    test('rejects unknown or odd values', () {
      expect(snapFrameRate(null), isNull);
      expect(snapFrameRate(0), isNull);
      expect(snapFrameRate(double.nan), isNull);
      expect(snapFrameRate(37.5), isNull);
      expect(snapFrameRate(1000), isNull);
    });
  });

  group('pickRefreshRate', () {
    test('plays broadcast rates at the highest multiple up to 60 Hz', () {
      expect(pickRefreshRate(25, chromecast), 50);
      expect(pickRefreshRate(50, chromecast), 50);
      expect(pickRefreshRate(29.97, chromecast), closeTo(59.94, 0.001));
      expect(pickRefreshRate(30, chromecast), closeTo(60, 0.001));
    });

    test('keeps film at its own rate and tells 23.976 from 24', () {
      expect(pickRefreshRate(23.976, chromecast), closeTo(23.976, 0.001));
      expect(pickRefreshRate(23.98, chromecast), closeTo(23.976, 0.001));
      expect(pickRefreshRate(24, chromecast), closeTo(24, 0.001));
    });

    test('uses 47.952 Hz for film when the display offers it', () {
      expect(
        pickRefreshRate(23.976, [...chromecast, 47.952048]),
        closeTo(47.952, 0.001),
      );
    });

    test('maps video above 60 fps to an exact fraction', () {
      expect(pickRefreshRate(100, chromecast), 50);
      expect(pickRefreshRate(120, chromecast), closeTo(60, 0.001));
    });

    test('never slows 60 fps video down to 30 Hz', () {
      expect(pickRefreshRate(60, [30.0]), isNull);
    });

    test('skips rates above 60 Hz', () {
      expect(pickRefreshRate(25, [100.0]), isNull);
    });

    test('returns null when nothing matches', () {
      expect(pickRefreshRate(25, [59.94, 60]), isNull);
      expect(pickRefreshRate(null, chromecast), isNull);
      expect(pickRefreshRate(25, const []), isNull);
    });
  });

  test('formats rates the way a TV menu shows them', () {
    expect(formatRefreshRate(60.000004), '60 Hz');
    expect(formatRefreshRate(59.94006), '59,94 Hz');
    expect(formatRefreshRate(23.976025), '23,976 Hz');
    expect(formatFrameRate(25.03), '25 fps');
    expect(formatFrameRate(23.98), '23,976 fps');
  });
}
