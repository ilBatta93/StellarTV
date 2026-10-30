import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/image_url.dart';

void main() {
  test('accepts TMDB paths with dashes and underscores', () {
    expect(
      cleanImageUrl('/a-b_C12.jpg'),
      'https://image.tmdb.org/t/p/w780/a-b_C12.jpg',
    );
  });
  test('falls through empty fields to the next usable one', () {
    expect(
      firstImageUrl(['null', '', null, '/still_1.png']),
      'https://image.tmdb.org/t/p/w780/still_1.png',
    );
  });
  test('100k normalizations stay fast', () {
    final sw = Stopwatch()..start();
    for (var i = 0; i < 100000; i++) {
      firstImageUrl(['', 'http://cdn.x/p$i.jpg']);
    }
    expect(sw.elapsedMilliseconds, lessThan(1500));
  });
}
