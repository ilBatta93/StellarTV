import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/epg_channel_match.dart';

void main() {
  test('shared tvg-id never gives +1 the base guide when +1 exists', () {
    final m = EpgMatcher(
      guideIds: {'Canale5.it', 'Canale5+1.it'},
      displayNames: {'Canale5.it': 'Canale 5', 'Canale5+1.it': 'Canale 5 +1'},
    );
    expect(
      m.match(name: 'IT: CANALE 5 +1 HD', tvgId: 'Canale5.it'),
      const EpgMatch('Canale5+1.it', 0),
    );
    expect(
      m.match(name: 'IT: CANALE 5 HD', tvgId: 'Canale5.it'),
      const EpgMatch('Canale5.it', 0),
    );
  });

  test('+1 without its own guide uses the base moved by one hour', () {
    final m = EpgMatcher(
      guideIds: {'Canale5.it'},
      displayNames: {'Canale5.it': 'Canale 5'},
    );
    expect(
      m.match(name: 'Canale 5 +1', tvgId: 'Canale5.it'),
      const EpgMatch('Canale5.it', 1),
    );
  });

  test('every display-name is used for matching', () {
    final m = EpgMatcher(
      guideIds: {'c5'},
      displayNames: {'c5': 'Canale 5${epgNameSeparator}Mediaset Canale5'},
    );
    expect(m.match(name: 'MEDIASET CANALE5 FHD'), const EpgMatch('c5', 0));
  });

  test('base channel never takes the +1 guide', () {
    final m = EpgMatcher(
      guideIds: {'Canale5+1.it'},
      displayNames: {'Canale5+1.it': 'Canale 5 +1'},
    );
    expect(m.match(name: 'Canale 5', tvgId: 'Canale5+1.it'), isNull);
  });
}
