import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/providers/history_provider.dart';
import 'package:stellar_tv/services/sync_service.dart';
import 'package:stellar_tv/services/favorites_service.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'forced account exit clears history even when null profile is unchanged',
    () async {
      SharedPreferences.setMockInitialValues({
        'local_watch_history': jsonEncode({
          'x': {
            'id': 'x',
            'title': 'Sample',
            'type': 'movie',
            'watched': '2026-10-18T12:00:00Z',
            'pos': 10,
            'dur': 100,
          },
        }),
      });
      final client = SupabaseClient(
        'https://example.test',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final service = SyncService(client),
          history = HistoryProvider(SyncService(client));
      await history.switchProfile(null);
      expect(history.entries.map((e) => e.contentId), ['x']);
      await service.signOut();
      await history.switchProfile(null, force: true);
      expect(history.entries, isEmpty);
      history.dispose();
      await client.dispose();
    },
  );
  test('account exit drains pending favorite writes before clearing local data', () async {
    SharedPreferences.setMockInitialValues({});
    final client = SupabaseClient('https://example.test', 'test', authOptions: const AuthClientOptions(autoRefreshToken: false));
    final service = FavoritesService();
    final pending = service.toggleFavorite(Channel(id: 'a', name: 'Sample', url: '', logo: '', group: '', type: ContentType.movie));
    await SyncService(client).signOut();
    await pending;
    expect(await service.getFavoriteIds(), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('vault_favorite_events_v1'), false);
    await client.dispose();
  });
}
