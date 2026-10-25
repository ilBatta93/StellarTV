import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../providers/history_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/sync_provider.dart';
import '../providers/ui_settings.dart';
import '../services/device_type_service.dart';
import '../services/tv_render_policy.dart';
import '../widgets/brand_intro.dart';
import '../widgets/brand_logo.dart';
import 'account_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'profile_picker_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  bool _navigated = false;
  bool _cloudChecked = false;
  int _initAttempts = 0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 3200),
      vsync: this,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryNavigate();
    });
  }

  Future<void> _tryNavigate() async {
    if (_navigated || !mounted) return;
    final app = context.read<AppProvider>();
    final sync = context.read<SyncProvider>();
    final history = context.read<HistoryProvider>();

    if (!app.isInitialized) {
      // Bounded wait: if startup never completes, fall through to the login
      // screen instead of leaving the app stuck on the splash forever.
      if (_initAttempts++ < 20) {
        Future.delayed(const Duration(milliseconds: 300), _tryNavigate);
        return;
      }
    }

    // If a sync code is configured, restore cloud data on startup: this is
    // what carries history, favorites and playlist credentials over to a new
    // device. Run once per launch, then continue navigating.
    // Every device needs a StellarTV account: it is what syncs the data.
    if (!sync.isSignedIn) {
      await sync.waitForSession();
      if (!mounted) return;
    }
    // The stored code may not be loaded yet on a cold start.
    if (sync.isSignedIn && sync.code == null) {
      await sync.load();
      if (!mounted) return;
    }

    if (!sync.isSignedIn) {
      // Guest mode: the user chose to use this device without an account.
      final guest = await AccountScreen.isGuest();
      if (!mounted) return;
      if (!guest) {
        _navigate(const AccountScreen());
        return;
      }
    }

    if (!_cloudChecked) {
      _cloudChecked = true;
      if (sync.code != null) {
        if (app.isAuthenticated) {
          // A configured device opens locally; the existing guarded restore
          // updates data independently without holding navigation.
          history.pullFromCloud().catchError((Object _) => false);
        } else {
          _restoreFromCloud(history, app);
          return;
        }
      }
    }

    if (!app.isAuthenticated) {
      _navigate(const LoginScreen());
      return;
    }

    // Authenticated: show the profile picker only when profiles exist and
    // none has been chosen on this device yet; otherwise go straight home.
    final needsProfile = await context.read<ProfileProvider>().needsSelection();
    if (!mounted) return;
    _navigate(needsProfile ? const ProfilePickerScreen() : const HomeScreen());
  }

  Future<void> _navigate(Widget target) async {
    _navigated = true;
    // Let the intro finish and hold the full logo briefly before leaving.
    if (_animController.isAnimating) {
      await _animController.forward().orCancel.catchError((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    if (!mounted) return;
    // Read the setting NOW, while the splash is still mounted. The transition
    // builder keeps running after this screen is replaced and disposed, so
    // looking up UiSettings from the splash context inside it throws
    // "Provider<UiSettings> not found for SplashScreen".
    final animate =
        TvRenderPolicy.startupFade(
          isTv: DeviceTypeService.isTv,
          animations: context.read<UiSettings>().animations,
        ) &&
        !MediaQuery.disableAnimationsOf(context);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => target,
        transitionDuration: animate
            ? const Duration(milliseconds: 300)
            : Duration.zero,
        reverseTransitionDuration: animate
            ? const Duration(milliseconds: 300)
            : Duration.zero,
        transitionsBuilder: (_, anim, _, child) {
          if (!animate) return child;
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  Future<void> _restoreFromCloud(
    HistoryProvider history,
    AppProvider app,
  ) async {
    // Cloud restore must never block launch: if the device is offline, the
    // code is unknown or the server is unreachable, fall through to the normal
    // flow after a short wait instead of staying on the splash forever.
    try {
      await history.pullFromCloud().timeout(
        const Duration(seconds: 8),
        onTimeout: () => false,
      );
    } catch (_) {
      // Ignore: the app continues with the data already on the device.
    }
    if (!mounted) return;
    _tryNavigate();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion =
        context.select<UiSettings, bool>((ui) => ui.animations) &&
        !MediaQuery.disableAnimationsOf(context);
    // Animation never gates routing; account and profile checks remain required.
    if (motion && !_animController.isAnimating && _animController.value == 0) {
      _animController.forward();
    } else if (!motion && _animController.value != 1) {
      _animController.stop();
      _animController.value = 1;
    }
    return Scaffold(
      backgroundColor: kBrandCanvas,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: kBrandCanvas),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _animController,
                  builder: (context, _) =>
                      BrandIntro(progress: _animController.value),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
