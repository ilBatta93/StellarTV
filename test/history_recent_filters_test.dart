import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/history_entry.dart';
import 'package:stellar_tv/screens/history_settings_screen.dart';
import 'package:stellar_tv/services/recent_live_channels.dart';

HistoryEntry _e(String id, ContentType t) => HistoryEntry(
  contentId: id,
  type: t,
  title: id,
  posterUrl: '',
  group: '',
  position: Duration.zero,
  duration: const Duration(minutes: 10),
  lastWatchedAt: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cronologia divisa tra film e serie', () {
    final all = [
      _e('m', ContentType.movie),
      _e('s', ContentType.series),
      _e('a', ContentType.anime),
      _e('l', ContentType.live),
    ];
    expect(filterHistory(all, HistoryFilter.all).length, 4);
    expect(filterHistory(all, HistoryFilter.movies).map((e) => e.contentId), [
      'm',
    ]);
    expect(filterHistory(all, HistoryFilter.series).map((e) => e.contentId), [
      's',
      'a',
    ]);
  });

  test('rimozione e svuotamento canali visti di recente', () async {
    SharedPreferences.setMockInitialValues({
      'recent_live_channels_v1': ['a', 'b', 'c'],
    });
    final r = RecentLiveChannels.instance;
    await r.remove('b');
    expect(r.ids, ['a', 'c']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('recent_live_channels_v1'), ['a', 'c']);
    await r.clear();
    expect(r.ids, isEmpty);
  });
}
