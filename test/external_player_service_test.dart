import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/services/external_player_service.dart';

Channel _channel(ContentType type, String url, {bool folder = false}) =>
    Channel(
      id: 'id',
      name: 'Titolo',
      url: url,
      logo: '',
      group: '',
      type: type,
      isSeriesFolder: folder,
    );

void main() {
  test('films and episodes on the network go to the external player', () {
    expect(
      ExternalPlayerService.canPlay(
        _channel(ContentType.movie, 'http://host/movie/u/p/1.mkv'),
      ),
      isTrue,
    );
    expect(
      ExternalPlayerService.canPlay(
        _channel(ContentType.series, 'https://host/series/u/p/2.mp4'),
      ),
      isTrue,
    );
  });

  test('live channels, offline copies and series folders stay inside', () {
    expect(
      ExternalPlayerService.canPlay(
        _channel(ContentType.live, 'http://host/live/u/p/3.ts'),
      ),
      isFalse,
    );
    expect(
      ExternalPlayerService.canPlay(
        _channel(ContentType.movie, '/data/user/0/tv.stellar.app/films/1.mkv'),
      ),
      isFalse,
    );
    expect(
      ExternalPlayerService.canPlay(
        _channel(ContentType.series, 'http://host/series', folder: true),
      ),
      isFalse,
    );
  });
}
