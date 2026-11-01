import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/providers/history_provider.dart';
import 'package:stellar_tv/services/playback_progress_writer.dart';
import 'package:stellar_tv/services/sync_service.dart';

Channel episode(String id) => Channel(
  id: id,
  name: 'Serie S01E${id.substring(2)}',
  url: 'https://example.invalid/$id',
  logo: '',
  group: '',
  type: ContentType.series,
  seriesKey: 'serie',
  seriesName: 'Serie',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('il punto di ripresa resta finché la visione non lo supera', () {
    const pending = Duration(minutes: 22);
    // Landed for a moment: saved, but the point stays pending.
    expect(resumeSample(pending, pending), ResumeSample.save);
    // The stream fell back near the start: never overwrite the point.
    expect(
      resumeSample(const Duration(minutes: 1, seconds: 5), pending),
      ResumeSample.skip,
    );
    expect(
      resumeSample(pending + resumeConfirmAfter, pending),
      ResumeSample.saveAndConfirm,
    );
  });

  test(
    'un titolo aperto e chiuso subito resta in Continua a guardare',
    () async {
      final client = SupabaseClient(
        'https://example.invalid',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final history = HistoryProvider(SyncService(client));
      await history.recordStart(episode('ep1'));
      expect(history.continueWatching.map((e) => e.contentId), ['ep1']);

      // The next episode opened and closed at once keeps the series listed.
      await history.updatePosition(
        'ep1',
        const Duration(minutes: 10),
        const Duration(minutes: 24),
      );
      await history.recordStart(episode('ep2'));
      expect(history.continueWatching.map((e) => e.contentId), ['ep2']);

      history.dispose();
      await client.dispose();
    },
  );
}
