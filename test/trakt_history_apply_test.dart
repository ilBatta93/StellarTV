import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/providers/history_provider.dart';
import 'package:stellar_tv/services/history_signals.dart';
import 'package:stellar_tv/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Trakt views apply without echo and never beat a newer choice',
    () async {
      SharedPreferences.setMockInitialValues({});
      final client = SupabaseClient(
        'https://example.test',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final history = HistoryProvider(SyncService(client));
      await history.switchProfile('p1');
      final signals = <HistorySignal>[];
      final sub = HistorySignals.stream.listen(signals.add);

      // A local "not watched" choice made now.
      await history.setManualWatched(['ep2'], false);
      await Future<void>.delayed(Duration.zero);
      expect(signals.single.kind, HistorySignalKind.markedUnwatched);
      signals.clear();

      final old = DateTime.utc(2026, 1, 1);
      await history.applyRemoteWatched({'ep1': old, 'ep2': old});
      await Future<void>.delayed(Duration.zero);
      expect(history.isWatched('ep1'), isTrue);
      expect(history.isWatched('ep2'), isFalse, reason: 'newer local choice');
      expect(signals, isEmpty, reason: 'remote views are not sent back');

      await history.refresh();
      expect(history.isWatched('ep1'), isTrue);

      await sub.cancel();
      history.dispose();
      await client.dispose();
    },
  );

  test('a Trakt pause point creates the resume point once', () async {
    SharedPreferences.setMockInitialValues({});
    final client = SupabaseClient(
      'https://example.test',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final history = HistoryProvider(SyncService(client));
    await history.switchProfile('p1');
    final movie = Channel(
      id: 'm1',
      name: 'Titolo di prova (2020)',
      url: 'http://example.test/m1',
      logo: '',
      group: 'Prova',
      type: ContentType.movie,
    );
    final at = DateTime.now().toUtc();
    await history.applyRemoteProgress(
      movie,
      const Duration(minutes: 30),
      const Duration(minutes: 100),
      at,
    );
    expect(history.entryFor('m1')?.position, const Duration(minutes: 30));
    // An older pause point does not move it back.
    await history.applyRemoteProgress(
      movie,
      const Duration(minutes: 10),
      const Duration(minutes: 100),
      at.subtract(const Duration(hours: 1)),
    );
    expect(history.entryFor('m1')?.position, const Duration(minutes: 30));
    history.dispose();
    await client.dispose();
  });
}
