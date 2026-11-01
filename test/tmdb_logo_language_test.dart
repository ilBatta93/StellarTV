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

  group('selectTitleLogo quality', () {
    test('a transparent logo beats a better-voted JPEG', () {
      final url = TmdbService.selectTitleLogo({
        'logos': [logo('/box.jpg', 'it', 9.0), logo('/clear.png', 'it', 4.0)],
      });
      expect(url, 'https://image.tmdb.org/t/p/w500/clear.png');
    });

    test('a wide wordmark beats a stacked one', () {
      final url = TmdbService.selectTitleLogo({
        'logos': [
          {...logo('/stacked.png', 'en', 6.0), 'width': 500, 'height': 600},
          {...logo('/wide.png', 'en', 5.0), 'width': 500, 'height': 120},
        ],
      });
      expect(url, 'https://image.tmdb.org/t/p/w500/wide.png');
    });
  });
}
