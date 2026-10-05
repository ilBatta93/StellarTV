import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'providers/app_provider.dart';
import 'providers/discover_provider.dart';
import 'providers/epg_provider.dart';
import 'providers/history_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/ui_settings.dart';
import 'screens/splash_screen.dart';
import 'services/profile_service.dart';
import 'services/device_type_service.dart';
import 'services/sync_service.dart';
import 'services/tmdb_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A widget that throws during build would otherwise leave the whole app on a
  // blank white screen on a real device. Show a readable fallback instead.
  ErrorWidget.builder = (details) => _StartupErrorView(details: details);
  MediaKit.ensureInitialized();
  await DeviceTypeService.initialize();
  if (DeviceTypeService.isTv) {
    // TV boxes have little RAM: cap decoded images to avoid being killed.
    PaintingBinding.instance.imageCache
      ..maximumSize = 250
      ..maximumSizeBytes = 80 << 20;
  }
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );
  runApp(const StellarTvApp());
}

/// Shown in place of a widget that fails to build, so a crash never presents
/// as a fully white screen with no explanation.
class _StartupErrorView extends StatelessWidget {
  final FlutterErrorDetails details;

  const _StartupErrorView({required this.details});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 40,
          ),
          const SizedBox(height: 12),
          const Text(
            'Si è verificato un errore. Riapri l\'app.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            details.exceptionAsString(),
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class StellarTvApp extends StatefulWidget {
  const StellarTvApp({super.key});

  @override
  State<StellarTvApp> createState() => _StellarTvAppState();
}

class _StellarTvAppState extends State<StellarTvApp> {
  late final AppProvider _appProvider;
  late final SyncProvider _syncProvider;
  late final HistoryProvider _historyProvider;
  late final ProfileProvider _profileProvider;
  final UiSettings _uiSettings = UiSettings()..load();

  @override
  void initState() {
    super.initState();
    final syncService = SyncService(Supabase.instance.client);
    final profileService = ProfileService(Supabase.instance.client);
    _appProvider = AppProvider()..init();
    _syncProvider = SyncProvider(syncService);
    _historyProvider = HistoryProvider(
      syncService,
      _appProvider,
      _syncProvider,
    );
    _profileProvider = ProfileProvider(profileService, syncService);
    // Load profiles at startup so the top-bar avatar and the splash routing
    // know which profile is active on this device.
    // Each profile has a private history; kids profiles see kids content only.
    _profileProvider.onSelectionChanged = (profile) {
      _historyProvider.switchProfile(profile?.id);
      _appProvider.setKidsMode(profile?.isKids ?? false);
    };
    ProfileProvider.savedSelectionIsKids(profileService).then((kids) {
      if (kids) _appProvider.setKidsMode(true);
    });
    _profileProvider.load();
    // The sync needs favorites from the app state and must reload the app
    // when credentials arrive from another device.
    _syncProvider.snapshotSource = () async => SnapshotPart(
      history: {},
      favoriteIds: _appProvider.favoriteIds.toList(),
      tmdbFavorites: _appProvider.tmdbFavorites.map((e) => e.toJson()).toList(),
    );
    _historyProvider.onCredentialsRestored = _appProvider.reloadFromStorage;
    _historyProvider.onSettingsRestored = () async {
      await _appProvider.reloadSettings();
      await _uiSettings.load();
    };
    // Profiles created/edited on other devices show up automatically.
    _historyProvider.onAfterAutoPull = () =>
        _profileProvider.load(silent: true);
    _historyProvider.startAutoSync();
    // Keep the cloud favorites table in step with the sync code: upload the
    // local list when a code is enabled/entered, stop mirroring when cleared.
    _syncProvider.onCodeReady = _appProvider.pushAllFavorites;
    _syncProvider.onCodeCleared = () async {
      // Sign-out wipes the device: drop the playlist, profiles and history
      // kept in memory so the next account starts clean.
      _appProvider.clearCloudCode();
      await _appProvider.logout();
      await _appProvider.reloadFromStorage();
      _historyProvider.switchProfile(null);
      await _profileProvider.load(silent: true);
    };
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
    _profileProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _appProvider),
        ChangeNotifierProvider.value(value: _syncProvider),
        ChangeNotifierProvider.value(value: _historyProvider),
        ChangeNotifierProvider.value(value: _profileProvider),
        ChangeNotifierProvider(create: (_) => DiscoverProvider(TmdbService())),
        ChangeNotifierProvider(create: (_) => EpgProvider(_appProvider)),
        ChangeNotifierProvider.value(value: _uiSettings),
      ],
      child: Builder(
        builder: (context) {
          final ui = context.watch<UiSettings>();
          return MaterialApp(
            title: 'StellarTV',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.darkTheme(
              accent: ui.accent,
              isTv: DeviceTypeService.isTv,
            ),
            darkTheme: AppTheme.darkTheme(
              accent: ui.accent,
              isTv: DeviceTypeService.isTv,
            ),
            themeMode: ThemeMode.dark,
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
