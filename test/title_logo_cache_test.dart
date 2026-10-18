import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/services/title_logo_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 1, 1);
  const logo = 'https://image.tmdb.org/t/p/w500/title.png';
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('saved logo is available on later presentations and expires', () async {
    await TitleLogoCache.write('movie_1', logo, now: now);
    expect((await TitleLogoCache.read('movie_1', now: now))?.url, logo);
    expect(
      await TitleLogoCache.read(
        'movie_1',
        now: now.add(const Duration(days: 31)),
      ),
      isNull,
    );
  });
  test('missing logo caches briefly, allowing later discovery', () async {
    await TitleLogoCache.write('tv_2', null, now: now);
    expect(await TitleLogoCache.read('tv_2', now: now), isNotNull);
    expect(
      await TitleLogoCache.read('tv_2', now: now.add(const Duration(hours: 7))),
      isNull,
    );
  });
  test(
    'concurrent writes preserve distinct titles and reject unrelated hosts',
    () async {
      await Future.wait([
        TitleLogoCache.write('1', logo, now: now),
        TitleLogoCache.write('2', logo, now: now),
      ]);
      expect((await TitleLogoCache.read('1', now: now))?.url, logo);
      expect((await TitleLogoCache.read('2', now: now))?.url, logo);
      await TitleLogoCache.write(
        '3',
        'https://foreign.test/logo.png',
        now: now,
      );
      expect(await TitleLogoCache.read('3', now: now), isNull);
      final prefs = await SharedPreferences.getInstance();
      final entries =
          jsonDecode(prefs.getString(TitleLogoCache.storageKey) ?? '{}') as Map;
      expect(entries.length, 2);
    },
  );
}
