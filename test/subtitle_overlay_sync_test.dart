import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/widgets/player/subtitle_overlay.dart';

void main() {
  test('advances position between engine reports while playing', () {
    expect(
      extrapolatePosition(
        const Duration(seconds: 10),
        const Duration(milliseconds: 200),
        playing: true,
      ),
      const Duration(milliseconds: 10200),
    );
  });
  test('never advances while paused', () {
    expect(
      extrapolatePosition(
        const Duration(seconds: 10),
        const Duration(milliseconds: 200),
        playing: false,
      ),
      const Duration(seconds: 10),
    );
  });
  test('caps extrapolation during stalls', () {
    expect(
      extrapolatePosition(
        const Duration(seconds: 10),
        const Duration(seconds: 5),
        playing: true,
      ),
      const Duration(milliseconds: 10600),
    );
  });
}
