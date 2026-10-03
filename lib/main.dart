import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'providers/app_provider.dart';
import 'providers/discover_provider.dart';
import 'providers/history_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/ui_settings.dart';
import 'screens/splash_screen.dart';
import 'services/sync_service.dart';
import 'services/tmdb_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
  runApp(const IlBattaTvApp());
}

class IlBattaTvApp extends StatefulWidget {
  const IlBattaTvApp({super.key});

  @override
  State<IlBattaTvApp> createState() => _IlBattaTvAppState();
}

class _IlBattaTvAppState extends State<IlBattaTvApp> {
  late final AppProvider _appProvider;
  late final SyncProvider _syncProvider;
  late final HistoryProvider _historyProvider;

  @override
  void initState() {
    super.initState();
    final syncService = SyncService(Supabase.instance.client);
    _appProvider = AppProvider()..init();
    _syncProvider = SyncProvider(syncService);
    _historyProvider =
        HistoryProvider(syncService, _appProvider, _syncProvider);
    // The sync needs favorites from the app state and must reload the app
    // when credentials arrive from another device.
    _syncProvider.snapshotSource = () async => SnapshotPart(
          history: {},
          favoriteIds: _appProvider.favoriteIds.toList(),
          tmdbFavorites:
              _appProvider.tmdbFavorites.map((e) => e.toJson()).toList(),
        );
    _historyProvider.onCredentialsRestored = _appProvider.reloadFromStorage;
    _appProvider.addListener(_onAppChanged);
    _syncProvider.load();
  }

  /// Any change to favorites schedules a cloud push (debounced).
  void _onAppChanged() => _syncProvider.schedulePush();

  @override
  void dispose() {
    _appProvider.removeListener(_onAppChanged);
    _appProvider.dispose();
    _historyProvider.dispose();
    _syncProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _appProvider),
        ChangeNotifierProvider.value(value: _syncProvider),
        ChangeNotifierProvider.value(value: _historyProvider),
        ChangeNotifierProvider(create: (_) => DiscoverProvider(TmdbService())),
        ChangeNotifierProvider(create: (_) => UiSettings()..load()),
      ],
      child: Builder(
        builder: (context) {
          final ui = context.watch<UiSettings>();
          return MaterialApp(
            title: 'ilBattaTV',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.darkTheme(accent: ui.accent),
            darkTheme: AppTheme.darkTheme(accent: ui.accent),
            themeMode: ThemeMode.dark,
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
