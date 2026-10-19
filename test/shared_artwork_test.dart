import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/tmdb_service.dart';

void main() {
  test('shared logo becomes TMDB image URL', () {
    final e = TmdbService.parseSharedLogo({
      'results': [
        {'tmdb_id': 1, 'logo_path': '/abc_1.png'},
      ],
    });
    expect(e?.url, 'https://image.tmdb.org/t/p/w500/abc_1.png');
  });
  test('known title without logo is cached as no logo', () {
    final e = TmdbService.parseSharedLogo({
      'results': [
        {'tmdb_id': 1, 'logo_path': null},
      ],
    });
    expect(e, isNotNull);
    expect(e!.url, isNull);
  });
  test('foreign URLs and failures fall back to direct lookup', () {
    expect(
      TmdbService.parseSharedLogo({
        'results': [
          {'tmdb_id': 1, 'logo_path': 'http://provider.invalid/x.png'},
        ],
      }),
      isNull,
    );
    expect(
      TmdbService.parseSharedLogo({
        'results': [null],
      }),
      isNull,
    );
  });
}
