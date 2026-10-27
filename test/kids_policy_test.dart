import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/kids_policy.dart';
import 'package:stellar_tv/services/kids_content_service.dart';
import 'package:stellar_tv/services/playback_work_policy.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';

void main() {
  test('universal ratings alone never authorize generic categories', () {
    expect(
      KidsPolicy.allows(
        category: 'Film 2024',
        genres: [35],
        certification: 'US:G',
      ),
      isFalse,
    );
    expect(
      KidsPolicy.allows(
        category: 'Cinema',
        genres: [10751],
        certification: 'US:PG',
      ),
      isFalse,
    );
    expect(
      KidsPolicy.allows(
        category: 'Cinema',
        genres: [16],
        certification: 'IT:T',
      ),
      isTrue,
    );
  });
  test('all forbidden genres and mixed categories veto children labels', () {
    for (final genre in KidsPolicy.blockedGenres) {
      expect(
        KidsPolicy.allows(
          category: 'Kids',
          genres: [16, genre],
          certification: 'US:G',
        ),
        isFalse,
      );
    }
    for (final category in [
      'Family Horror',
      'Kids Action',
      'Cartoni Crime',
      'Famiglia Drama',
      'Kids News',
      'Kids Romance',
      'Kids Reality',
      'Kids Thriller',
    ]) {
      expect(KidsPolicy.allows(category: category), isFalse);
    }
  });
  test('unknown requires explicit primary children category', () {
    for (final cert in ['', 'UNKNOWN', 'UNRATED']) {
      expect(
        KidsPolicy.allows(category: 'Family', certification: cert),
        isFalse,
      );
      expect(
        KidsPolicy.allows(category: 'Cartoni Animati', certification: cert),
        isTrue,
      );
      expect(KidsPolicy.allows(category: 'Kids', certification: cert), isTrue);
      expect(
        KidsPolicy.allows(
          category: 'Cinema',
          genres: [10751, 16],
          certification: cert,
        ),
        isFalse,
      );
    }
  });
  test('valid family rating allowed but mature rating overrides Animation', () {
    expect(
      KidsPolicy.allows(category: 'Famiglia', certification: 'IT:T'),
      isTrue,
    );
    for (final rating in [
      'US:R',
      'US:PG-13',
      'US:TV-14',
      'US:TV-MA',
      'IT:14',
    ]) {
      expect(
        KidsPolicy.allows(
          category: 'Animation',
          genres: [16],
          certification: rating,
        ),
        isFalse,
      );
    }
  });
  test('title and brand names cannot authorize live channels', () {
    final service = KidsContentService();
    for (final type in ContentType.values) {
      Channel item(String group, [String name = 'Disney Kids']) => Channel(
        id: '1',
        name: name,
        url: '',
        logo: '',
        group: group,
        type: type,
      );
      expect(service.isKidsContent(item('Cinema')), isFalse);
      expect(service.isKidsContent(item('Cartoni Animati', 'Peppa')), isTrue);
      expect(service.isKidsContent(item('Kids Horror', 'Peppa')), isFalse);
      expect(service.isKidsContent(item('Kids', 'Killer')), isFalse);
      expect(service.isKidsContent(item('Family')), isFalse);
    }
  });

  test('indexed kids warmup queues a facet key without a title file', () {
    final owner = Object();
    PlaybackWorkPolicy.instance.update(owner, cloudBlocked: true);
    addTearDown(() => PlaybackWorkPolicy.instance.remove(owner));
    final service = KidsContentService();
    addTearDown(service.dispose);
    service.requestIndexed([(key: 'movie:il padrino', title: 'Il Padrino')]);
    expect(service.queuedKeys, ['movie:il padrino']);
  });
}
