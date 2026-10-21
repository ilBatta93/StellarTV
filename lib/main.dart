import 'package:flutter/material.dart';

import 'navigation/app_routes.dart';

import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'providers/app_provider.dart';
import 'providers/discover_provider.dart';
import 'providers/reactions_provider.dart';
import 'providers/epg_provider.dart';
import 'providers/history_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/ui_settings.dart';
import 'screens/splash_screen.dart';
import 'services/profile_service.dart';
import 'services/device_type_service.dart';
import 'services/device_identity.dart';
import 'services/remote_signout_service.dart';
import 'screens/account_screen.dart';
import 'services/expiry_reminder_service.dart';
import 'services/tv_remote_keys.dart';
import 'services/sync_service.dart';
import 'services/download_service.dart';
import 'services/tmdb_service.dart';
import 'services/app_update_service.dart';
import 'services/app_migration_service.dart';
import 'services/sync_hooks.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A widget that throws during build would otherwise leave the whole app on a
  // blank white screen on a real device. Show a readable fallback instead.
  ErrorWidget.builder = (details) => _StartupErrorView(details: details);
  MediaKit.ensureInitialized();
  // Post-update safety net: once per installed build, clears only rebuildable
  // derived caches. Never touches user data and never blocks startup.
  await AppMigrationService.run();
  await DeviceTypeService.initialize();
  if (DeviceTypeService.isTv) {
    // TV boxes have little RAM: cap decoded images to avoid being killed.
    PaintingBinding.instance.imageCache
      ..maximumSize = 250
      ..maximumSizeBytes = 80 << 20;
    TvRemoteKeys.install();
  } else {
    // Phones: generous but bounded decoded-image memory.
    PaintingBinding.instance.imageCache
      ..maximumSize = 400
      ..maximumSizeBytes = 150 << 20;
  }
  await DeviceIdentity.initialize();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
    // Lets the account website name this device's sessions precisely.
    headers: {'User-Agent': DeviceIdentity.userAgent},
  );
  final savedKids = await ProfileProvider.savedSelectionIsKids(
    ProfileService(Supabase.instance.client),
  );
  runApp(StellarTvApp(initialKids: savedKids));
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
  final bool initialKids;
  const StellarTvApp({super.key, this.initialKids = false});

  @override
  State<StellarTvApp> createState() => _StellarTvAppState();
}

class _StellarTvAppState extends State<StellarTvApp> {
  late final AppProvider _appProvider;
  late final SyncProvider _syncProvider;
  late final HistoryProvider _historyProvider;
  late final ProfileProvider _profileProvider;
  final ReactionsProvider _reactions = ReactionsProvider();
  final UiSettings _uiSettings = UiSettings()..load();

  @override
  void initState() {
    super.initState();
    AppUpdateService.scheduleStartupCheck();
    final syncService = SyncService(Supabase.instance.client);
    final profileService = ProfileService(Supabase.instance.client);
    _appProvider = AppProvider()
      ..setKidsMode(widget.initialKids)
      ..init();
    _syncProvider = SyncProvider(syncService);
    _historyProvider = HistoryProvider(
      syncService,
      _appProvider,
      _syncProvider,
    );
    _historyProvider.setWatchedPercent(_uiSettings.watchedPercent);
    _profileProvider = ProfileProvider(profileService, syncService);
    // Load profiles at startup so the top-bar avatar and the splash routing
    // know which profile is active on this device.
    // Each profile has a private history; kids profiles see kids content only.
    _reactions.onSaved = _syncProvider.schedulePush;
    // Every saved preference (player, look, layouts...) reaches the cloud.
    SyncHooks.onSettingsChanged = _syncProvider.schedulePush;
    _reactions.reload();
    _profileProvider.onSelectionChanged = (profile) {
      _reactions.switchProfile(profile?.id);
      _historyProvider.switchProfile(profile?.id);
      _appProvider.setKidsMode(profile?.isKids ?? false);
    };
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
      await ExpiryReminderService.instance.reloadSettings();
      await _uiSettings.load();
      await _reactions.reload();
    };
    // Profiles created/edited on other devices show up automatically.
    _historyProvider.onAfterAutoPull = () =>
        _profileProvider.load(silent: true);
    // The first cloud pull is not needed to draw Home: start it right after
    // the first frame so startup and the first scroll stay smooth. Pushes
    // from user actions remain instant (schedulePush is independent).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _historyProvider.startAutoSync();
      });
    });
    // Keep the cloud favorites table in step with the sync code: upload the
    // local list when a code is enabled/entered, stop mirroring when cleared.
    _syncProvider.onCodeReady = _appProvider.pushAllFavorites;
    _syncProvider.onCodeCleared = () async {
      // Sign-out wipes the device: drop the playlist, profiles and history
      // kept in memory so the next account starts clean.
      _appProvider.clearCloudCode();
      await _appProvider.logout();
      await _appProvider.reloadFromStorage();
      await _historyProvider.switchProfile(null, force: true);
      await _reactions.switchProfile(null);
      await _profileProvider.load(silent: true);
    };
    _appProvider.addListener(_onAppChanged);
    _uiSettings.addListener(_onUiSettingsChanged);
    // Reminders are not needed for the first frame: start after it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 8), () {
        ExpiryReminderService.instance.start(_appProvider.xtreamCredentials);
        DownloadService.instance.init();
      });
    });
    _syncProvider.load();
    _remoteSignout = RemoteSignoutService(Supabase.instance.client, () async {
      await _syncProvider.signOut();
      appNavigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AccountScreen()),
        (_) => false,
      );
    });
    // Remote sign-out polling is a background check: start it after the
    // first frame instead of competing with the initial Home build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 6), () {
        if (mounted) _remoteSignout.start();
      });
    });
  }

  late final RemoteSignoutService _remoteSignout;

  String _uiSignature = '';

  void _onUiSettingsChanged() {
    if (!_uiSettings.loaded) return;
    _historyProvider.setWatchedPercent(_uiSettings.watchedPercent);
    final sig = _uiSettings.signature;
    if (sig == _uiSignature) return;
    final first = _uiSignature.isEmpty;
    _uiSignature = sig;
    if (!first) _syncProvider.schedulePush();
  }

  /// Any change to favorites schedules a cloud push (debounced).
  String _favSignature = '';

  /// Any real change to favorites is pushed to the cloud instantly; other
  /// app notifications (loading progress etc.) do not trigger uploads.
  void _onAppChanged() {
    final sig =
        '${_appProvider.favoriteIds.length}:'
        '${Object.hashAllUnordered(_appProvider.favoriteIds)}:'
        '${Object.hashAll(_appProvider.tmdbFavorites.map((e) => e.key))}';
    if (sig == _favSignature) return;
    final first = _favSignature.isEmpty;
    _favSignature = sig;
    if (!first) _syncProvider.schedulePush();
  }

  @override
  void dispose() {
    _remoteSignout.dispose();
    _appProvider.removeListener(_onAppChanged);
    _uiSettings.removeListener(_onUiSettingsChanged);
    _uiSettings.dispose();
    _reactions.dispose();
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
        ChangeNotifierProvider.value(value: _reactions),
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
            navigatorKey: appNavigatorKey,
            navigatorObservers: [OpenRoutesObserver.instance],
            home: const SplashScreen(),
            // "Dimensione testo" in Personalizzazione scales every label.
            builder: (context, child) {
              final factor = ui.textScaleFactor;
              if (factor == 1.0 || child == null)
                return child ?? const SizedBox();
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(
                  textScaler: TextScaler.linear(
                    mq.textScaler.scale(1) * factor,
                  ),
                ),
                child: child,
              );
            },
          );
        },
      ),
    );
  }
}
