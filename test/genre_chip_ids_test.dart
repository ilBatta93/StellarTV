import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/screens/catalog_page.dart';

void main() {
  test('Genre ids without a name get no chip instead of failing', () {
    final ids = genreChipIds(
      {28: 4, 10759: 2, 18: 1},
      {10759: 'Azione e avventura', 18: 'Dramma'},
    );
    expect(ids, [10759, 18]);
  });

  test('No named genre leaves the bar empty', () {
    expect(genreChipIds({28: 3}, {18: 'Dramma'}), isEmpty);
  });
}
