import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/providers/history_provider.dart';
import 'package:stellar_tv/services/sync_service.dart';
import 'package:stellar_tv/services/playback_progress_writer.dart';

Channel episode(String id) => Channel(
  id: id,
  name: id,
  url: 'https://example.invalid/$id',
  logo: '',
  group: '',
  type: ContentType.series,
  seriesKey: 's',
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('90 percent then backward, forward and restart always replace only the current episode', () async {
    final client = SupabaseClient(
      'https://example.invalid',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final sync = SyncService(client);
    final history = HistoryProvider(sync);
    await history.switchProfile('viewer');
    await history.recordStart(episode('e1'));
    await history.recordStart(episode('e2'));
    await history.updatePosition(
      'e2',
      const Duration(seconds: 400),
      const Duration(seconds: 1000),
    );
    await history.setManualWatched(['e2'], true);
    for (final seconds in [900, 200, 750, 0, 50]) {
      await history.updatePosition(
        'e1',
        Duration(seconds: seconds),
        const Duration(seconds: 1000),
      );
      await history.refresh();
      expect(history.entryFor('e1')?.position.inSeconds, seconds);
      expect(history.entryFor('e2')?.position.inSeconds, 400);
      expect(history.manualWatched('e2'), true);
      expect(
        (await sync.loadLocalHistory(profileId: 'viewer'))['e1']['pos'],
        seconds,
      );
    }
    history.dispose();
    await client.dispose();
  });
  test('a queued backward position wins and completion blocks only its own session', () async {
    final writer = PlaybackProgressWriter();
    final gate = Completer<void>();
    var position = 900;
    final first = writer.save(() async {
      await gate.future;
      position = 900;
    });
    final second = writer.save(() async {
      position = 200;
    });
    gate.complete();
    await Future.wait([first, second]);
    expect(position, 200);
    await writer.complete(() async {
      position = 1000;
    });
    await writer.save(() async {
      position = 900;
    });
    expect(position, 1000);
    await PlaybackProgressWriter().save(() async {
      position = 0;
    });
    expect(position, 0);
  });
}
