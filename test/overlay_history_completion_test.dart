import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/providers/history_provider.dart';
import 'package:stellar_tv/services/sync_service.dart';
import 'package:stellar_tv/services/player_settings_service.dart';
import 'package:stellar_tv/services/playback_progress_writer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Overlay completion reads back as fully watched in the active profile only', () async {
    final client = SupabaseClient('https://example.invalid', 'test');
    final sync = SyncService(client);
    final history = HistoryProvider(sync);
    final settings = PlayerSettingsService();
    final episode = Channel(id: 'ep1', name: 'Series S1E1',
      url: 'https://example.invalid/episode', logo: '', group: '',
      type: ContentType.series, seriesKey: 'series', seriesName: 'Series');
    await history.switchProfile('alberto');
    await history.recordStart(episode);
    await history.updatePosition(episode.id, const Duration(minutes: 15), const Duration(minutes: 20));
    await settings.saveResumePosition(episode.url, const Duration(minutes: 15));
    final writer = PlaybackProgressWriter();
    await writer.complete(() async {
      await history.markWatched(episode, duration: const Duration(minutes: 20));
      await settings.saveResumePosition(episode.url, null);
    });
    await writer.save(() => history.updatePosition(episode.id,
      const Duration(minutes: 15), const Duration(minutes: 20)));
    expect(history.entryFor('ep1')?.progress, 1.0);
    expect(history.isWatched('ep1'), isTrue);
    expect(history.continueWatching, isEmpty);
    expect(await settings.getResumePosition(episode.url), isNull);
    final stored = await sync.loadLocalHistory(profileId: 'alberto');
    expect((stored['ep1'] as Map)['pos'], 1200);
    expect((stored['ep1'] as Map)['dur'], 1200);
    await history.switchProfile('kids');
    expect(history.entryFor('ep1'), isNull);
    await history.switchProfile('alberto');
    expect(history.entryFor('ep1')?.progress, 1.0);
    history.dispose(); client.auth.stopAutoRefresh();
  });
}
