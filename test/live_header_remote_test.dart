import 'dart:io';
import 'dart:ui' as image_ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stellar_tv/models/channel.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/epg_program.dart';
import 'package:stellar_tv/providers/app_provider.dart';
import 'package:stellar_tv/providers/epg_provider.dart';
import 'package:stellar_tv/providers/ui_settings.dart';
import 'package:stellar_tv/screens/live_page.dart';
import 'package:stellar_tv/theme/app_theme.dart';
import 'package:stellar_tv/widgets/poster_card.dart';
import 'package:stellar_tv/widgets/tv_catalog_navigation.dart';
import 'package:stellar_tv/widgets/tv_focusable.dart';
import 'october_live_multiview_test.dart' as fixtures;

class LogoApp extends fixtures.TestApp {
  @override
  List<Channel> get channels => [
    Channel(id: 'uno', name: 'RAI 4K', url: 'https://example.invalid/live',
      logo: 'https://example.invalid/rai.png', group: 'TV', type: ContentType.live),
    fixtures.channel('due'),
    fixtures.channel('tre'),
  ];
}

class OptionalEpg extends fixtures.TestEpg {
  OptionalEpg(super.app, this.empty);
  final bool empty;
  @override
  List<EpgProgram> programmesFor(Channel c) => empty ? [] : super.programmesFor(c);
  @override
  EpgProgram? nowFor(Channel c) => programmesFor(c).firstOrNull;
}

void focusStop(WidgetTester tester, Finder finder) {
  final stop = finder.evaluate().first;
  final excluded = find.descendant(of: find.byWidget(stop.widget), matching: find.byType(ExcludeFocus)).first;
  Focus.of(tester.element(excluded)).requestFocus();
}

bool focusedInside(Finder finder) {
  final primary = FocusManager.instance.primaryFocus;
  final element = primary?.context;
  if (element == null) return false;
  final targets = finder.evaluate().toSet();
  var found = targets.contains(element);
  element.visitAncestorElements((ancestor) {
    if (targets.contains(ancestor)) found = true;
    return !found;
  });
  return found;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  fixtures.mainSetupForRemote();
  setUp(() async {
    for (final family in ['Sora', 'Manrope', 'MaterialIcons']) {
      final loader = FontLoader(family)..addFont(rootBundle.load(
        family == 'MaterialIcons' ? 'fonts/MaterialIcons-Regular.otf' : 'assets/fonts/$family.ttf'));
      await loader.load();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => '/tmp/stv/test-image-cache',
    );
  });
  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    for (final empty in [false, true]) {
      testWidgets('Live Up tools/menu, all icons and channel logos ${size.width} empty=$empty', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = LogoApp(), epg = OptionalEpg(LogoApp(), empty), settings = UiSettings();
        final menu = List.generate(4, (i) => FocusNode(debugLabel: 'menu$i'));
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(MultiProvider(providers: [
          ChangeNotifierProvider<AppProvider>.value(value: app),
          ChangeNotifierProvider<EpgProvider>.value(value: epg),
          ChangeNotifierProvider<UiSettings>.value(value: settings),
        ], child: MaterialApp(theme: AppTheme.darkTheme(isTv: true), home: Scaffold(
          body: RepaintBoundary(key: boundaryKey, child: TvCatalogMenu(
            onMenu: menu[0].requestFocus,
            child: Column(children: [
              Row(children: [for (var i = 0; i < menu.length; i++)
                TvFocusable(focusNode: menu[i], onPressed: () {},
                  child: SizedBox(width: 120, height: 52,
                    child: Center(child: Text(['Diretta', 'Home', 'Film', 'Serie TV'][i])))),
              ]),
              const Expanded(child: LivePage(active: false)),
            ]),
          )),
        ))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.widget<PosterImage>(find.descendant(
          of: find.byKey(const ValueKey('live-logo-uno-30.0')),
          matching: find.byType(PosterImage))).url, 'https://example.invalid/rai.png');
        final first = find.widgetWithText(TvFocusable, 'RAI 4K').first;
        final search = find.ancestor(of: find.byTooltip('Cerca'), matching: find.byType(TvFocusable));
        final tools = [search,
          find.ancestor(of: find.byTooltip('Filtri e categorie'), matching: find.byType(TvFocusable)),
          find.ancestor(of: find.byTooltip('Ordina: Predefinito'), matching: find.byType(TvFocusable)),
          find.ancestor(of: find.byTooltip('MultiView'), matching: find.byType(TvFocusable)),
          find.ancestor(of: find.byTooltip('Guida TV (EPG)'), matching: find.byType(TvFocusable)),
        ];
        // First channel and every upper EPG cell go to Search, then the main menu.
        for (var column = 0; column < (empty ? 2 : 4); column++) {
          focusStop(tester, first);
          await tester.pumpAndSettle();
          for (var x = 0; x < column; x++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await tester.pumpAndSettle();
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.pumpAndSettle();
          expect(focusedInside(search), true, reason: 'Up from guide column $column');
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.pumpAndSettle();
          expect(menu[0].hasFocus, true);
          for (var tab = 1; tab < 4; tab++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await tester.pumpAndSettle();
            expect(menu[tab].hasFocus, true);
          }
        }
        // Lower rows move upward through the list before reaching tools.
        focusStop(tester, first);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(focusedInside(find.widgetWithText(TvFocusable, 'Canale due').first), true);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(focusedInside(first), true);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(focusedInside(search), true);
        for (var i = 1; i < tools.length; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
          expect(focusedInside(tools[i]), true, reason: 'Tool $i must be one focus stop');
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.pumpAndSettle();
          expect(menu[0].hasFocus, true);
          focusStop(tester, tools[i]);
          await tester.pumpAndSettle();
        }
        focusStop(tester, find.byKey(const ValueKey('live-preview-focus')));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(focusedInside(search), true, reason: 'Preview Up must reach toolbar');
        // OK opens categories, Back returns to the same icon.
        focusStop(tester, tools[1]);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(find.text('Tutti'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(focusedInside(tools[1]), true);
        // Search opens only with OK, Back restores the search icon.
        focusStop(tester, search);
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        if (find.byType(TextField).evaluate().isNotEmpty) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        }
        expect(find.byType(TextField), findsNothing);
        expect(focusedInside(search), true);
        expect(tester.takeException(), isNull);
        final boundary = boundaryKey.currentContext?.findRenderObject();
        if (boundary is RenderRepaintBoundary) {
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final data = await image.toByteData(format: image_ui.ImageByteFormat.png);
            if (data != null) await File('/tmp/stv/oct15-live-${size.width.toInt()}-$empty.png').writeAsBytes(data.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
        for (final node in menu) { node.dispose(); }
        epg.dispose(); app.dispose(); settings.dispose();
      });
    }
  }
}