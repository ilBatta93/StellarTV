import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/custom_category.dart';
import 'package:stellar_tv/models/streaming_platform.dart';
import 'package:stellar_tv/services/platform_catalog_service.dart';

Channel _movie(String id, String name, {String group = 'Film'}) => Channel(
  id: id,
  name: name,
  url: 'u',
  logo: '',
  group: group,
  type: ContentType.movie,
);

void main() {
  test('Crunchyroll is shared by movie and series platform filters', () {
    final p = StreamingPlatform.byName('Crunchyroll');
    expect(p?.providerIds, '283');
    expect(p?.region, 'IT');
    if (p == null) return;
    expect(
      belongsToPlatform(
        p,
        _movie('cr-film', 'Titolo', group: 'Crunchyroll'),
        {},
      ),
      isTrue,
    );
    final series = Channel(
      id: 'cr-tv',
      name: 'Titolo',
      url: 'u',
      logo: '',
      group: 'Crunchyroll',
      type: ContentType.series,
    );
    expect(belongsToPlatform(p, series, {}), isTrue);
    expect(belongsToPlatform(p, _movie('other', 'Animazione'), {}), isFalse);
  });
  test('saved order wins, new categories keep their default place', () {
    expect(applyCategoryOrder(['A', 'B', 'C', 'D'], ['C', 'Gone', 'A']), [
      'C',
      'A',
      'B',
      'D',
    ]);
  });

  test('moving a category stays inside the list', () {
    expect(moveCategory(['A', 'B', 'C'], 'C', -1), ['A', 'C', 'B']);
    expect(moveCategory(['A', 'B', 'C'], 'A', -1), ['A', 'B', 'C']);
    expect(moveCategory(['A', 'B', 'C'], 'C', -2), ['C', 'A', 'B']);
  });

  test('personal categories survive a save and reload', () {
    const c = CustomCategory(
      id: 'movie-1',
      name: 'Serata',
      type: ContentType.movie,
      itemIds: ['10', '20'],
    );
    final back = CustomCategory.tryParse(c.toJson())!;
    expect(back.name, 'Serata');
    expect(back.type, ContentType.movie);
    expect(back.itemIds, ['10', '20']);
    expect(
      CustomCategory.tryParse({'id': 'x', 'name': ' ', 'type': 'movie'}),
      isNull,
    );
  });

  test('Disney+ is a Home platform with its TMDB provider id', () {
    final disney = StreamingPlatform.byName('Disney+');
    expect(disney, isNotNull);
    expect(disney!.providerIds, '337');
  });

  test('platform membership: TMDB match or provider tag', () {
    final netflix = StreamingPlatform.byName('Netflix')!;
    expect(belongsToPlatform(netflix, _movie('1', 'Titolo'), {'1'}), isTrue);
    expect(
      belongsToPlatform(
        netflix,
        _movie('2', 'Titolo', group: 'NETFLIX FILM'),
        {},
      ),
      isTrue,
    );
    expect(belongsToPlatform(netflix, _movie('3', 'Titolo [NF]'), {}), isTrue);
    expect(belongsToPlatform(netflix, _movie('4', 'Titolo'), {'1'}), isFalse);
    final disney = StreamingPlatform.byName('Disney+')!;
    expect(
      belongsToPlatform(disney, _movie('5', 'X', group: 'Disney+ Film'), {}),
      isTrue,
    );
    expect(
      belongsToPlatform(disney, _movie('6', 'Disney classico'), {}),
      isFalse,
    );
  });
}
