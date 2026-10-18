import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/tmdb_service.dart';

Map<String, dynamic> logo(String path, String? language, double vote) => {
  'file_path': path,
  'iso_639_1': language,
  'vote_average': vote,
};

void main() {
  group('selectTitleLogo language filter', () {
    test('ignores logos in other languages (e.g. Japanese)', () {
      final url = TmdbService.selectTitleLogo({
        'logos': [logo('/ja.png', 'ja', 9.0), logo('/en.png', 'en', 1.0)],
      });
      expect(url, 'https://image.tmdb.org/t/p/w500/en.png');
    });

    test('ignores untagged logos, which can carry any language', () {
      final url = TmdbService.selectTitleLogo({
        'logos': [logo('/untagged.png', null, 9.0)],
      });
      expect(url, isNull);
    });

    test('prefers Italian over English', () {
      final url = TmdbService.selectTitleLogo({
        'logos': [logo('/en.png', 'en', 9.0), logo('/it.png', 'it', 1.0)],
      });
      expect(url, 'https://image.tmdb.org/t/p/w500/it.png');
    });

    test('returns null when only other languages exist', () {
      final url = TmdbService.selectTitleLogo({
        'logos': [logo('/ja.png', 'ja', 9.0), logo('/ko.png', 'ko', 8.0)],
      });
      expect(url, isNull);
    });
  });
}
