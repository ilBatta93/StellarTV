import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/screens/player_screen.dart';

void main() {
  test('single press moves by one step', () => expect(tvScrubMultiplier(false, 0), 1));
  test('holding starts at 3x', () => expect(tvScrubMultiplier(true, 1), 3));
  test('holding longer accelerates', () => expect(tvScrubMultiplier(true, 25), 9));
  test('acceleration is capped at 30x', () => expect(tvScrubMultiplier(true, 500), 30));
}
