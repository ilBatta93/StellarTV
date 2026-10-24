import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/title_matching.dart';

void main() {
  test('dots and year removed', () {
    expect(displayTitle('Cave.Diving.(2024)'), 'Cave Diving');
  });
  test('3D kept', () {
    expect(displayTitle('Avatar 3D (2009)'), 'Avatar (3D)');
  });
  test('quality tags removed', () {
    expect(displayTitle('Crave 1080p ITA'), 'Crave');
  });
  test('audiobook detection', () {
    expect(isAudiobook('Il nome della rosa', 'AUDIOLIBRI'), true);
    expect(isAudiobook('Matrix', 'Film'), false);
  });
}
