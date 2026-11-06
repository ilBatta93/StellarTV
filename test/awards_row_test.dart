import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/awards.dart';
import 'package:stellar_tv/models/home_layout_preferences.dart';
import 'package:stellar_tv/models/tmdb_item.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/screens/home_rows_screen.dart';
import 'package:stellar_tv/services/awards_service.dart';
import 'package:stellar_tv/services/device_type_service.dart';
import 'package:stellar_tv/widgets/awards_row.dart';

const _json = {
  'generated': '2026-11-06',
  'categories': [
    {'id': 'oscar_picture', 'award': 'oscar', 'label': 'Miglior film'},
    {'id': 'emmy_limited', 'award': 'emmy', 'label': 'Miniserie'},
  ],
  'years': {
    '2025': {
      'oscar_picture': [
        {'id': 2, 'media': 'movie', 'title': 'Vincitore', 'winner': true},
        {'id': 1, 'media': 'movie', 'title': 'Candidato', 'winner': false},
      ],
      'emmy_limited': [
        {'id': 7, 'media': 'tv', 'title': 'Serie', 'winner': true},
        {'id': 8, 'media': 'movie', 'title': 'Film TV', 'winner': false},
      ],
    },
    '2024': {
      'oscar_picture': [
        {'id': 3, 'media': 'movie', 'title': 'Vecchio', 'winner': true},
      ],
      'broken': 'x',
    },
    'nope': {},
  },
};

TmdbItem _item(AwardNominee n) => TmdbItem(
  id: n.id,
  mediaType: n.movie ? 'movie' : 'tv',
  title: n.title,
  overview: '',
  posterPath: null,
  backdropPath: null,
  voteAverage: 7,
  popularity: 1,
  releaseDate: '',
);

class _FakeAwards extends AwardsService {
  _FakeAwards() : super(client: null);
  final catalogValue = AwardsCatalog.fromJson(_json);
  @override
  Future<AwardsCatalog> catalog() async => catalogValue;
  @override
  Future<List<TmdbItem>> items(List<AwardNominee> nominees) async =>
      nominees.map(_item).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog reads years, categories and types, skipping bad parts', () {
    final c = AwardsCatalog.fromJson(_json);
    expect(c.yearsDesc, [2025, 2024]);
    expect(c.categoriesIn(2024).map((e) => e.id), ['oscar_picture']);
    expect(c.categoriesIn(2025).last.fullLabel, 'Emmy · Miniserie');
    final limited = c.nominees(2025, 'emmy_limited');
    expect(limited.map((n) => n.movie), [false, true]);
    expect(c.nominees(2025, 'oscar_picture').first.winner, isTrue);
    expect(AwardsCatalog.fromJson('x').isEmpty, isTrue);
  });

  test('the awards row is a Home row: named, hidden and moved like the '
      'others', () async {
    final rows = HomeRows.defaults(tv: false, platforms: const ['Netflix']);
    expect(rows.indexOf(HomeRows.awards), rows.indexOf(HomeRows.topWeek) + 1);
    expect(homeRowLabel(HomeRows.awards), 'Oscar ed Emmy');
    expect(
      HomeRows.visible(rows, {HomeRows.awards}),
      isNot(contains(HomeRows.awards)),
    );
    // The settings save the whole order: the row can go first.
    final moved = [HomeRows.awards, ...rows.where((r) => r != HomeRows.awards)];
    expect(HomeRows.arrange(rows, moved).first, HomeRows.awards);
    SharedPreferences.setMockInitialValues({});
    final ui = UiSettings();
    await ui.load();
    await ui.setHomeRowVisible(HomeRows.awards, false);
    final reloaded = UiSettings();
    await reloaded.load();
    expect(reloaded.homeHiddenRows, {HomeRows.awards});
  });

  testWidgets('shows the latest year, winner first with a trophy', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('stellartv/device'),
          (_) async => false,
        );
    await DeviceTypeService.initialize();
    SharedPreferences.setMockInitialValues({});
    final ui = UiSettings();
    await ui.load();
    final opened = <TmdbItem>[];
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: ui,
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [AwardsRow(service: _FakeAwards(), onOpen: opened.add)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2025'), findsOneWidget);
    expect(find.text('Oscar · Miglior film'), findsOneWidget);
    expect(find.byType(AwardWinnerBadge), findsOneWidget);
    final winner = tester.getTopLeft(find.text('Vincitore').last);
    final other = tester.getTopLeft(find.text('Candidato'));
    expect(winner.dx, lessThan(other.dx));

    await tester.tap(find.text('Candidato'));
    expect(opened.single.id, 1);

    // Another year from the picker; its category is kept when present.
    await tester.tap(find.text('2025'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2024').last);
    await tester.pumpAndSettle();
    expect(find.text('Vecchio'), findsOneWidget);
    expect(find.text('Oscar · Miglior film'), findsOneWidget);
  });
}
