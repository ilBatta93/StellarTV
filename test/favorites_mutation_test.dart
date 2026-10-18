import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/tmdb_item.dart';
import 'package:stellar_tv/services/favorites_service.dart';
import 'package:stellar_tv/services/personal_vault.dart';

Channel channel(String id) => Channel(
  id: id,
  name: 'Sample',
  url: '',
  logo: '',
  group: '',
  type: ContentType.movie,
);
const item = TmdbItem(
  id: 42,
  mediaType: 'movie',
  title: 'Sample',
  overview: '',
  posterPath: null,
  backdropPath: null,
  voteAverage: 0,
  popularity: 0,
  releaseDate: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('parallel local additions preserve both favorite IDs', () async {
    final service = FavoritesService();
    await Future.wait([
      service.toggleFavorite(channel('a')),
      service.toggleFavorite(channel('b')),
    ]);
    expect(await service.getFavoriteIds(), {'a', 'b'});
  });
  test(
    'parallel double toggle removes favorite and retains removal event',
    () async {
      final service = FavoritesService();
      await Future.wait([
        service.toggleFavorite(channel('a')),
        service.toggleFavorite(channel('a')),
      ]);
      expect(await service.getFavoriteIds(), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(
          prefs.getString('vault_favorite_events_v1') ?? '{}',
        )['c:a']['deleted'],
        true,
      );
    },
  );
  test(
    'parallel metadata double toggle does not leave stale membership',
    () async {
      final service = FavoritesService();
      await Future.wait([
        service.toggleTmdbFavorite(item),
        service.toggleTmdbFavorite(item),
      ]);
      expect(await service.getTmdbFavorites(), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(
          prefs.getString('vault_favorite_events_v1') ?? '{}',
        )['t:movie_42']['deleted'],
        true,
      );
    },
  );
  test(
    'explicit unresolved favorite import supersedes its removal marker',
    () async {
      final service = FavoritesService();
      await service.recordEvent('c:unknown', true);
      await service.importFavorites(['unknown'], []);
      final prefs = await SharedPreferences.getInstance();
      final merged = PersonalVault.merge({}, {
        'favorite_ids': (await service.getFavoriteIds()).toList(),
        'profile_histories': {
          PersonalVault.favoriteLane: jsonDecode(
            prefs.getString('vault_favorite_events_v1') ?? '{}',
          ),
        },
      });
      expect(merged['favorite_ids'], ['unknown']);
      expect(
        merged['profile_histories'][PersonalVault
            .favoriteLane]['c:unknown']['deleted'],
        false,
      );
    },
  );
  test(
    'new local addition follows a queued remote removal without resurrection races',
    () async {
      final service = FavoritesService();
      await Future.wait([
        service.applyEncrypted({
          'profile_histories': {
            PersonalVault.favoriteLane: {
              'c:a': {'deleted': true, 'watched': '2020-01-01T00:00:00Z'},
            },
          },
        }),
        service.toggleFavorite(channel('a')),
      ]);
      expect(await service.getFavoriteIds(), {'a'});
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(
          prefs.getString('vault_favorite_events_v1') ?? '{}',
        )['c:a']['deleted'],
        false,
      );
    },
  );
}
