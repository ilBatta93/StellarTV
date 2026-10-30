import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stellar_tv/providers/discover_provider.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/services/tmdb_service.dart';
import 'package:stellar_tv/models/title_trailer.dart';
import 'package:stellar_tv/models/tmdb_item.dart';
import 'package:stellar_tv/widgets/trailer_button.dart';
import 'package:stellar_tv/widgets/tv_focusable.dart';

import 'home_banner_remote_test.dart' as fixture;
import 'october_live_multiview_test.dart' as remote;

class TrailerService extends TmdbService {
  @override
  Future<TitleTrailer?> trailer(TmdbItem item) async =>
      const TitleTrailer(key: 'abcDEF12345', language: 'it');
}

void main() {
  remote.mainSetupForRemote();
  testWidgets('Remote OK opens the trailer inside the app', (tester) async {
    String? opened;
    TrailerButton.opener = (_, t) async => opened = t.key;
    addTearDown(() => TrailerButton.opener = null);
    final service = DiscoverProvider(TrailerService()), settings = UiSettings();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DiscoverProvider>.value(value: service),
          ChangeNotifierProvider<UiSettings>.value(value: settings),
        ],
        child: MaterialApp(
          home: Scaffold(body: TrailerButton(item: fixture.item(7, 'Film'))),
        ),
      ),
    );
    await tester.pump();
    final stop = find.byType(TvFocusable);
    final child = find
        .descendant(of: stop, matching: find.byType(ExcludeFocus))
        .first;
    Focus.of(tester.element(child)).requestFocus();
    await tester.pump();
    final focus = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.select, platform: 'android');
    await tester.pump();
    expect(opened, 'abcDEF12345');
    expect(FocusManager.instance.primaryFocus, same(focus));
    await tester.pumpWidget(const SizedBox());
    service.dispose();
    settings.dispose();
  });
}
