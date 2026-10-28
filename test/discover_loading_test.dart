import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/streaming_platform.dart';
import 'package:stellar_tv/models/tmdb_item.dart';
import 'package:stellar_tv/providers/discover_provider.dart';
import 'package:stellar_tv/services/tmdb_service.dart';

class FakeTmdb extends TmdbService {
  int trendingCalls = 0, active = 0, maxActive = 0, platformCalls = 0;
  @override
  Future<List<TmdbItem>> trending(String type) async { trendingCalls++; return []; }
  @override
  Future<PlatformTops> platformTop(StreamingPlatform platform) async {
    platformCalls++; active++;
    if (active > maxActive) maxActive = active;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    active--; return const PlatformTops();
  }
}
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Concurrent loads join one refresh even after trending is complete', () async {
    final tmdb = FakeTmdb(); final provider = DiscoverProvider(tmdb);
    final first = provider.load();
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await Future.wait([first, provider.load(), provider.load(force: true)]);
    expect(tmdb.trendingCalls, 2);
    expect(tmdb.platformCalls, StreamingPlatform.all.length);
    provider.dispose();
  });
  test('Platform scans are bounded to two simultaneous tasks', () async {
    final tmdb = FakeTmdb(); final provider = DiscoverProvider(tmdb);
    await provider.load(); expect(tmdb.maxActive, 2); provider.dispose();
  });
  test('Completed refresh stays fresh on later page visits', () async {
    final tmdb = FakeTmdb(); final provider = DiscoverProvider(tmdb);
    await provider.load(); await provider.load();
    expect(tmdb.trendingCalls, 2); provider.dispose();
  });
}