import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/image_cache_service.dart';

void main() {
  const poster = 'https://image.tmdb.org/t/p/w500/abc.jpg';
  const backdrop = 'https://image.tmdb.org/t/p/w1280/abc.jpg';
  test('grid poster uses smallest covering size', () {
    expect(
      tmdbSizedUrl(poster, 320),
      'https://image.tmdb.org/t/p/w342/abc.jpg',
    );
    expect(
      tmdbSizedUrl(poster, 128),
      'https://image.tmdb.org/t/p/w185/abc.jpg',
    );
  });
  test('never upscales or touches large or unknown widths', () {
    expect(tmdbSizedUrl(poster, 640), poster);
    expect(tmdbSizedUrl(poster, null), poster);
    expect(
      tmdbSizedUrl(backdrop, 700),
      'https://image.tmdb.org/t/p/w780/abc.jpg',
    );
    expect(
      tmdbSizedUrl('https://provider.example/x.jpg', 100),
      'https://provider.example/x.jpg',
    );
  });
}
