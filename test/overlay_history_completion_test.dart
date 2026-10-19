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
  test(
    '94 percent completion survives local reload with real progress unchanged',
    () async {
      final client = SupabaseClient('https://example.invalid', 'test');
      final sync = SyncService(client);
      final history = HistoryProvider(sync);
      await history.switchProfile('viewer');
      for (final type in [ContentType.movie, ContentType.series]) {
        final channel = Channel(
          id: type.name,
          name: type.name,
          url: 'https://example.invalid/${type.name}',
          logo: '',
          group: '',
          type: type,
        );
        await history.recordStart(channel);
        await history.updatePosition(
          channel.id,
          const Duration(seconds: 3360),
          const Duration(minutes: 60),
        );
        expect(history.isWatched(channel.id), isFalse);
        expect(
          history.continueWatching.any((e) => e.contentId == channel.id),
          isTrue,
        );
        await history.updatePosition(
          channel.id,
          const Duration(minutes: 57),
          const Duration(minutes: 60),
        );
        expect(history.isWatched(channel.id), isTrue);
        expect(
          history.continueWatching.any((e) => e.contentId == channel.id),
          isFalse,
        );
      }
      final stored = await sync.loadLocalHistory(profileId: 'viewer');
      for (final id in ['movie', 'series']) {
        expect((stored[id] as Map)['pos'], 3420);
        expect((stored[id] as Map)['dur'], 3600);
      }
      await history.switchProfile('other');
      expect(history.entries, isEmpty);
      await history.switchProfile('viewer');
      for (final id in ['movie', 'series']) {
        expect(history.isWatched(id), isTrue);
        expect(history.entryFor(id)?.position, const Duration(minutes: 57));
      }
      expect(history.continueWatching, isEmpty);
      history.dispose();
      client.auth.stopAutoRefresh();
    },
  );
  test(
    'Overlay completion reads back as fully watched in the active profile only',
    () async {
      final client = SupabaseClient('https://example.invalid', 'test');
      final sync = SyncService(client);
      final history = HistoryProvider(sync);
      final settings = PlayerSettingsService();
      final episode = Channel(
        id: 'ep1',
        name: 'Series S1E1',
        url: 'https://example.invalid/episode',
        logo: '',
        group: '',
        type: ContentType.series,
        seriesKey: 'series',
        seriesName: 'Series',
      );
      await history.switchProfile('alberto');
      await history.recordStart(episode);
      await history.updatePosition(
        episode.id,
        const Duration(minutes: 15),
        const Duration(minutes: 60),
      );
      await settings.saveResumePosition(
        episode.url,
        const Duration(minutes: 15),
      );
      final writer = PlaybackProgressWriter();
      await writer.complete(() async {
        await history.markWatched(
          episode,
          duration: const Duration(minutes: 60),
        );
        await settings.saveResumePosition(episode.url, null);
      });
      await writer.save(
        () => history.updatePosition(
          episode.id,
          const Duration(minutes: 15),
          const Duration(minutes: 60),
        ),
      );
      expect(history.entryFor('ep1')?.progress, 1.0);
      expect(history.isWatched('ep1'), isTrue);
      expect(history.continueWatching, isEmpty);
      expect(await settings.getResumePosition(episode.url), isNull);
      final stored = await sync.loadLocalHistory(profileId: 'alberto');
      expect((stored['ep1'] as Map)['pos'], 1200);
      expect((stored['ep1'] as Map)['dur'], 3600);
      await history.switchProfile('kids');
      expect(history.entryFor('ep1'), isNull);
      await history.switchProfile('alberto');
      expect(history.entryFor('ep1')?.progress, 1.0);
      history.dispose();
      client.auth.stopAutoRefresh();
    },
  );
}
