import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/services/recent_live_channels.dart';

void main() {
  test('il canale aperto per ultimo va in cima, senza doppioni', () {
    expect(RecentLiveChannels.push(['live_1', 'live_2', 'live_3'], 'live_2'), [
      'live_2',
      'live_1',
      'live_3',
    ]);
  });

  test('la lista tiene al massimo 50 canali', () {
    final ids = [for (var i = 0; i < 50; i++) 'live_$i'];
    final out = RecentLiveChannels.push(ids, 'live_new');
    expect(out.length, 50);
    expect(out.first, 'live_new');
    expect(out, isNot(contains('live_49')));
  });

  test('i canali aperti restano salvati sul dispositivo', () async {
    SharedPreferences.setMockInitialValues({});
    await RecentLiveChannels.instance.record('live_7');
    await RecentLiveChannels.instance.record('live_9');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('recent_live_channels_v1'), [
      'live_9',
      'live_7',
    ]);
  });
}
