import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:stellar_tv/services/catalog_sort.dart';
import 'package:stellar_tv/services/title_matching.dart';

void main() {
  test('known scores order the ids and omit the rest', () {
    const names = ['Plain Title', 'Higher 2011', 'Lower 2010'];
    final scores = {
      parseTitle('Higher 2011').key('movie'): 8.4,
      parseTitle('Lower 2010').key('movie'): 6.1,
    };
    final ranked = rankKnownTitleIds(
      ['plain', 'high', 'low'],
      names,
      'movie',
      scores,
    );
    expect(ranked, ['high', 'low']);
  });

  test('equal scores keep the incoming alphabetical order', () {
    final order = rankedPositions(Float64List.fromList([7, 0, 9, 7]));
    expect(order, [2, 0, 3]);
  });
}
