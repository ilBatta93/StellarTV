import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/providers/history_provider.dart';
import 'package:stellar_tv/services/sync_service.dart';

Channel episode() => Channel(
  id: 'ep',
  name: 'Episode',
  url: 'https://example.invalid/ep',
  logo: '',
  group: '',
  type: ContentType.series,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('playing samples stay in memory until pause, seek or exit', () async {
    final client = SupabaseClient(
      'https://example.invalid',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final sync = SyncService(client);
    final history = HistoryProvider(sync);
    await history.recordStart(episode());
    const runtime = Duration(minutes: 20);

    final playing = await history.updatePosition(
      'ep',
      const Duration(seconds: 30),
      runtime,
      periodic: true,
    );
    expect(playing, isFalse);
    expect(history.entryFor('ep')?.position, const Duration(seconds: 30));
    expect((await sync.loadLocalHistory())['ep']['pos'], 0);

    final paused = await history.updatePosition(
      'ep',
      const Duration(seconds: 45),
      runtime,
    );
    expect(paused, isTrue);
    expect((await sync.loadLocalHistory())['ep']['pos'], 45);

    final again = await history.updatePosition(
      'ep',
      const Duration(seconds: 55),
      runtime,
      periodic: true,
    );
    expect(again, isFalse);
    expect(history.entryFor('ep')?.position, const Duration(seconds: 55));
    expect((await sync.loadLocalHistory())['ep']['pos'], 45);

    final exited = await history.updatePosition(
      'ep',
      const Duration(seconds: 55),
      runtime,
    );
    expect(exited, isTrue);
    expect((await sync.loadLocalHistory())['ep']['pos'], 55);

    history.dispose();
    await client.dispose();
  });

  test(
    'a burst keeps both partial snapshots in one preferences write',
    () async {
      final client = SupabaseClient(
        'https://example.invalid',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final service = SyncService(client);
      final manual = service.saveLocalHistory({
        'manual': {
          'id': 'manual',
          'type': '__stellar_seen_v1',
          'pos': 1,
          'watched': '2026-10-21T00:00:00.000Z',
        },
      });
      final playback = service.saveLocalHistory({
        'ep': {
          'id': 'ep',
          'title': 'Episode',
          'pos': 12,
          'dur': 100,
          'watched': '2026-10-21T00:00:01.000Z',
        },
      });
      await Future.wait([manual, playback]);
      final stored = await service.loadLocalHistory();
      expect(stored['manual']['type'], '__stellar_seen_v1');
      expect(stored['ep']['pos'], 12);
      await client.dispose();
    },
  );
}
