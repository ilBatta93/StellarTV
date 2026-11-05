import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/providers/app_provider.dart';
import 'package:stellar_tv/services/personal_vault.dart';
import 'package:stellar_tv/services/sync_service.dart';
import 'package:stellar_tv/services/title_metadata_store.dart';

// Work moved off the TV's UI thread at launch must give the same answers
// it gave on the UI thread.
void main() {
  Map<String, dynamic> entry(String watched, {String? type, int? pos}) => {
    'watched': watched,
    'type': ?type,
    'pos': ?pos,
  };

  test('the push merge matches the plain merge and spots no change', () async {
    final remote = PersonalVault.clean({
      'history': {'a': entry('2026-11-01T10:00:00Z')},
      'settings': {'theme': 'dark'},
    });
    final local = PersonalVault.clean({
      'history': {'b': entry('2026-11-02T10:00:00Z')},
      'settings': {'theme': 'dark'},
    });
    final out = await SyncService.mergeForPush(remote, local, null);
    expect(
      PersonalVault.canonical(out.merged),
      PersonalVault.canonical(PersonalVault.merge(remote, local)),
    );
    expect(out.unchanged, isFalse);
    final again = await SyncService.mergeForPush(out.merged, local, null);
    expect(again.unchanged, isTrue);
  });

  test(
    'a saved history keeps only manual choices under the snapshot',
    () async {
      final existing = jsonEncode({
        'old': entry('2026-11-01T10:00:00Z'),
        'seen': entry(
          '2026-11-03T10:00:00Z',
          type: '__stellar_seen_v1',
          pos: 1,
        ),
      });
      final snapshot = {
        'new': entry('2026-11-02T10:00:00Z'),
        'seen': entry(
          '2026-11-02T10:00:00Z',
          type: '__stellar_seen_v1',
          pos: 2,
        ),
      };
      final encoded = await SyncService.encodeHistoryOffUi(existing, snapshot);
      final saved = jsonDecode(encoded!) as Map<String, dynamic>;
      expect(saved.keys.toSet(), {'seen', 'new'});
      expect(saved['seen']['pos'], 1);
      expect(await SyncService.encodeHistoryOffUi(encoded, snapshot), isNull);
    },
  );

  test('a TMDB title matches the same year, else a title without one', () {
    expect(AppProvider.pickMatchSlot('1995', const []), isNull);
    expect(
      AppProvider.pickMatchSlot('1995', const [
        (slot: 1, name: 'Heat'),
        (slot: 2, name: 'Heat 2022'),
        (slot: 3, name: 'Heat (1995)'),
      ]),
      3,
    );
    expect(
      AppProvider.pickMatchSlot('1995', const [
        (slot: 1, name: 'Heat 2022'),
        (slot: 2, name: 'Heat'),
      ]),
      2,
    );
    expect(
      AppProvider.pickMatchSlot('1995', const [(slot: 1, name: 'Heat 2022')]),
      isNull,
    );
    expect(
      AppProvider.pickMatchSlot('', const [
        (slot: 4, name: 'Heat 2022'),
        (slot: 5, name: 'Heat'),
      ]),
      4,
    );
  });

  test('timed entries walk safely while values are put', () {
    final store = TitleMetadataStore<String>(
      fileName: 'timed_entries_v1.json',
      encode: (v) => v,
      decode: (v) => v as String?,
    );
    addTearDown(store.dispose);
    store.put('a', 'x');
    store.put('b', 'y');
    final seen = <String>[];
    for (final entry in store.timedEntries()) {
      seen.add(entry.key);
      store.put('c${seen.length}', 'z');
    }
    expect(seen, ['a', 'b']);
  });

  test('a large vault merges the same off this isolate', () async {
    Map<String, dynamic> rows(int from) => {
      for (var i = from; i < from + PersonalVault.offUiRows; i++)
        't$i': entry(
          '2026-10-${(i % 28 + 1).toString().padLeft(2, '0')}T10:00:00Z',
        ),
    };
    final remote = PersonalVault.clean({'history': rows(0)});
    final local = PersonalVault.clean({'history': rows(100)});
    expect(PersonalVault.historyRows(remote), PersonalVault.offUiRows);
    final out = await SyncService.mergeForPush(remote, local, null);
    expect(
      PersonalVault.canonical(out.merged),
      PersonalVault.canonical(PersonalVault.merge(remote, local)),
    );
    final big = rows(0);
    final encoded = await SyncService.encodeHistoryOffUi(null, big);
    expect((jsonDecode(encoded!) as Map).length, big.length);
  });
}
