import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../providers/history_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/sync_provider.dart';
import '../providers/ui_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
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
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  bool _navigated = false;
  bool _cloudChecked = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeIn),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _animController.forward();

    Future.delayed(const Duration(milliseconds: 2200), _tryNavigate);
  }

  Future<void> _tryNavigate() async {
    if (_navigated || !mounted) return;
    final app = context.read<AppProvider>();
    final sync = context.read<SyncProvider>();
    final history = context.read<HistoryProvider>();

    if (!app.isInitialized) {
      Future.delayed(const Duration(milliseconds: 300), _tryNavigate);
      return;
    }

    // If a sync code is configured, restore cloud data on startup: this is
    // what carries history, favorites and playlist credentials over to a new
    // device. Run once per launch, then continue navigating.
    if (!_cloudChecked) {
      _cloudChecked = true;
      if (sync.code != null) {
        _restoreFromCloud(history, app);
        return;
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

  void _navigate(Widget target) {
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => target,
        transitionsBuilder: (_, anim, _, child) {
          if (!context.read<UiSettings>().animations) return child;
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  Future<void> _restoreFromCloud(
      HistoryProvider history, AppProvider app) async {
    await history.pullFromCloud();
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.18),
              AppColors.background,
            ],
            radius: 0.9,
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  BrandMark(size: 104),
                  SizedBox(height: 24),
                  BrandWordmark(fontSize: 34),
                  SizedBox(height: 8),
                  Text(
                    'TV in diretta, film e serie in un unico posto',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
