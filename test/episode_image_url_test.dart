import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/xtream_service.dart';

void main() {
  test('Episode artwork rejects empty values and completes TMDB paths', () {
    expect(cleanImageUrl(null), '');
    expect(cleanImageUrl('null'), '');
    expect(cleanImageUrl('  '), '');
    expect(cleanImageUrl('/abc123.jpg'), 'https://image.tmdb.org/t/p/w780/abc123.jpg');
    expect(cleanImageUrl('//cdn.x/a.jpg'), 'https://cdn.x/a.jpg');
    expect(cleanImageUrl('http://cdn.x/a b.jpg'), 'http://cdn.x/a%20b.jpg');
  });
}
