import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stellar_tv/models/tmdb_item.dart';
import 'package:stellar_tv/providers/discover_provider.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/services/tmdb_service.dart';
import 'package:stellar_tv/widgets/home_art.dart';

class LogoTmdb extends TmdbService {
  final result = Completer<String?>();
  @override
  Future<String?> titleLogo(TmdbItem item) => result.future;
}

void main() {
  testWidgets('Title text stays visible until a logo replaces it', (
    tester,
  ) async {
    final tmdb = LogoTmdb();
    final item = TmdbItem(
      id: 1,
      mediaType: 'movie',
      title: 'Titolo',
      overview: '',
      posterPath: null,
      backdropPath: null,
      voteAverage: 0,
      popularity: 0,
      releaseDate: '2026-01-01',
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => DiscoverProvider(tmdb)),
          ChangeNotifierProvider(create: (_) => UiSettings()),
        ],
        child: MaterialApp(
          home: Scaffold(body: HomeTitleArt(item: item)),
        ),
      ),
    );
    expect(find.text('Titolo'), findsOneWidget);
    tmdb.result.complete(null);
    await tester.pump();
    expect(find.byType(Text), findsOneWidget);
  });
}
