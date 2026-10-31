import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/services/title_versions.dart';

Channel film(String id, String name) => Channel(
  id: id,
  name: name,
  url: 'https://example.invalid/$id',
  logo: '',
  group: 'Film',
  type: ContentType.movie,
);

void main() {
  final versions = TitleVersions.instance;
  final copies = [
    film('a', 'Titolo (2020) [4K]'),
    film('b', 'Titolo (2020)'),
    film('c', 'Titolo (2020) 1080p'),
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    versions.reset();
  });

  test('etichette di qualità leggibili', () {
    expect(copies.map(TitleVersions.labelOf), ['4K', 'Standard', 'Full HD']);
  });

  test('senza scelta parte il Full HD, il 4K per ultimo', () {
    expect(versions.pick(copies).id, 'c');
    expect(versions.pick([copies[0], copies[1]]).id, 'b');
  });

  test('una copia già iniziata ha la precedenza sulla qualità', () {
    expect(versions.pick(copies, startedId: 'a').id, 'a');
  });

  test('la versione scelta resta per quel titolo', () async {
    await versions.choose(copies[0]);
    expect(versions.pick(copies, startedId: 'b').id, 'a');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('title_version_choice_v1'), contains('"a"'));
  });
}
