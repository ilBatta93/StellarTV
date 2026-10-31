import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/services/live_variants.dart';

void main() {
  final variants = LiveVariants.instance;

  LiveVariantIndex index(Map<String, String> names) => LiveVariantIndex.build([
    for (final e in names.entries) (id: e.key, name: e.value),
  ]);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    variants.reset();
  });

  test('le parole di qualità non contano, numeri e +1 sì', () {
    expect(parseLiveName('RAI 1 UFHD').key, 'rai 1');
    expect(parseLiveName('Rai 1 ᴴᴰ').key, 'rai 1');
    expect(parseLiveName('Rai 1 Full HD').quality, LiveQuality.fullHd);
    expect(parseLiveName('RAI 1 4K').quality, LiveQuality.uhd);
    expect(parseLiveName('Rai 1').quality, LiveQuality.standard);
    expect(parseLiveName('Rai 1 HEVC').quality, LiveQuality.hevc);
    expect(parseLiveName('Rai 2 HD').key, 'rai 2');
    expect(parseLiveName('Canale 5 +1 HD').key, 'canale 5 +1');
  });

  test('solo i canali con più versioni formano un gruppo', () {
    final built = index({
      'a': 'RAI 1',
      'b': 'RAI 1 HD',
      'c': 'RAI 1 FHD',
      'd': 'RAI 1 UFHD',
      'e': 'RAI 2 HD',
      'f': 'Canale 5 +1',
      'g': 'Canale 5',
    });
    variants.apply(built);
    expect(variants.idsOf('c'), ['a', 'b', 'c', 'd']);
    expect(variants.idsOf('e'), ['e']);
    expect(variants.labelOf('e'), isNull);
    expect(variants.labelOf('d'), '4K');
    expect(variants.idsOf('f'), ['f']);
  });

  test('parte il Full HD, poi l\'HD; il 4K solo se è l\'unico', () {
    variants.apply(
      index({'a': 'RAI 1', 'b': 'RAI 1 HD', 'c': 'RAI 1 FHD', 'd': 'RAI 1 4K'}),
    );
    expect(variants.pick(['a', 'b', 'c', 'd']), 'c');
    expect(variants.pick(['a', 'b', 'd']), 'b');
    expect(variants.pick(['a', 'd']), 'a');
    expect(variants.pick(['d']), 'd');
  });

  test('la guida tiene una riga per canale, al posto della prima', () {
    variants.apply(
      index({'a': 'RAI 1', 'x': 'RAI 2', 'b': 'RAI 1 FHD', 'c': 'RAI 1 4K'}),
    );
    expect(variants.collapse(['a', 'x', 'b', 'c']), ['b', 'x']);
    expect(variants.collapse(['a', 'x', 'b', 'c'], keep: 'c'), ['c', 'x']);
    final untouched = ['x', 'a'];
    expect(identical(variants.collapse(untouched), untouched), isTrue);
  });

  test('la versione scelta resta per quel canale', () async {
    variants.apply(index({'a': 'RAI 1 HD', 'b': 'RAI 1 FHD'}));
    expect(variants.pick(['a', 'b']), 'b');
    await variants.choose('a');
    expect(variants.pick(['a', 'b']), 'a');
    expect(variants.collapse(['b', 'a']), ['a']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('live_variant_choice_v1'), contains('"a"'));
  });
}
