import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/services/download_service.dart';

Channel _c(String url, ContentType type, {bool folder = false}) => Channel(
  id: 'x',
  name: 'x',
  url: url,
  logo: '',
  group: '',
  type: type,
  isSeriesFolder: folder,
);

void main() {
  test('film ed episodi diretti sono scaricabili', () {
    expect(
      DownloadService.canDownload(
        _c('http://h/movie/u/p/1.mkv', ContentType.movie),
      ),
      isTrue,
    );
    expect(
      DownloadService.canDownload(
        _c('https://h/series/u/p/2.mp4', ContentType.series),
      ),
      isTrue,
    );
  });
  test('dirette, HLS e cartelle serie sono escluse', () {
    expect(
      DownloadService.canDownload(_c('http://h/live/1.ts', ContentType.live)),
      isFalse,
    );
    expect(
      DownloadService.canDownload(
        _c('http://h/a/index.m3u8', ContentType.movie),
      ),
      isFalse,
    );
    expect(
      DownloadService.canDownload(
        _c('http://h/s', ContentType.series, folder: true),
      ),
      isFalse,
    );
  });
  test('estensione del file locale', () {
    expect(DownloadService.extensionFor('http://h/movie/1.mkv?t=1'), 'mkv');
    expect(DownloadService.extensionFor('http://h.it/movie/1'), 'mp4');
  });
}
