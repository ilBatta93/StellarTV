import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stellar_tv/providers/history_provider.dart';
import 'package:stellar_tv/services/sync_service.dart';
import 'package:stellar_tv/services/personal_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('manual seasons survive reload, reversals, clear and profile switch without fake history', () async {
    SharedPreferences.setMockInitialValues({});
    final client = SupabaseClient('https://example.test', 'test', authOptions: const AuthClientOptions(autoRefreshToken: false));
    final service = SyncService(client);
    final history = HistoryProvider(service);
    await history.switchProfile('p1');
    await history.setManualWatched(['s1e1', 's1e2'], true, seriesId: 'series1');
    expect(history.isWatched('s1e1'), true);
    expect(history.entries, isEmpty);
    await history.refresh();
    expect(history.isWatched('s1e2'), true);
    await history.remove('series1');
    await history.refresh();
    expect(history.isWatched('s1e2'), false);
    await history.setManualWatched(['s1e2'], true, seriesId: 'series1');
    await history.setManualWatched(['s1e1'], false);
    await history.refresh();
    expect(history.isWatched('s1e1'), false);
    await history.switchProfile('p2');
    expect(history.isWatched('s1e2'), false);
    await history.switchProfile('p1');
    expect(history.isWatched('s1e2'), true);
    await history.clear();
    await history.refresh();
    expect(history.isWatched('s1e2'), false);
    history.dispose();
    await client.dispose();
  });
  test('late playback save cannot erase a manual choice', () async {
    SharedPreferences.setMockInitialValues({});
    final client = SupabaseClient('https://example.test', 'test', authOptions: const AuthClientOptions(autoRefreshToken: false));
    final service = SyncService(client);
    await service.saveLocalHistory({'manual': {'id': 'manual', 'type': '__stellar_seen_v1', 'pos': 1, 'watched': '2026-10-21T00:00:00Z'}});
    await service.saveLocalHistory({'ep': {'id': 'ep', 'title': 'Episode', 'pos': 12, 'dur': 100, 'watched': '2026-10-21T00:00:01Z'}});
    final stored = await service.loadLocalHistory();
    expect(stored['manual']['pos'], 1);
    expect(stored['ep']['pos'], 12);
    await client.dispose();
  });
  test('500 playback cap preserves all manual reversals through JSON and sanitizer', () {
    final raw = {'manual': {'id': 'manual', 'type': '__stellar_seen_v1', 'pos': 0, 'watched': '2026-10-01T00:00:00Z'}, for (var i = 0; i < 501; i++) '$i': {'id': '$i', 'pos': i, 'watched': '2026-10-21T00:00:00Z'}};
    final snapshot = PersonalVault.clean(jsonDecode(jsonEncode({'history': raw})));
    final capped = PersonalVault.capHistory(snapshot['history']);
    expect(capped.length, 501);
    expect(capped['manual']['pos'], 0);
  });
}