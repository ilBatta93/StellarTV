import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/widgets/player/live_channel_picker.dart';

Channel _ch(String id, String group) => Channel(
  id: id,
  name: id,
  url: 'http://tv.example/live/u/p/$id.ts',
  logo: '',
  group: group,
  type: ContentType.live,
);

void main() {
  final rai = _ch('live_1', 'TV SAT [VS]');
  final other = _ch('live_2', 'SPORT');
  final groups = [
    LiveChannelGroup('Tutti', [rai, other]),
    LiveChannelGroup('SPORT', [other]),
    LiveChannelGroup('TV SAT [VS]', [rai]),
  ];

  test('l\'elenco canali si apre sulla categoria del canale in onda', () {
    expect(initialLiveGroup(groups, rai), 2);
    expect(initialLiveGroup(groups, other), 1);
  });

  test('canale senza la sua categoria: prima lista che lo contiene', () {
    final orphan = _ch('live_2', 'NASCOSTA');
    expect(initialLiveGroup(groups, orphan), 0);
  });
}
