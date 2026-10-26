import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFF000000);
  static const surface = Color(0xFF1C1C1E);
  static const card = Color(0xFF2C2C2E);
  static const glass = Color(0xE61C1C1E);
  static const overlay = Color(0x99000000);
  static const clear = Color(0x00000000);
  static const onOverlay = textPrimary;
  static const onOverlaySecondary = Color(0xFFCCCCD0);
  static const onOverlayDisabled = Color(0xFF77777B);
  static const overlayControl = Color(0xB32C2C2E);
  static const track = Color(0xFF4A4A4E);
  static const bufferedTrack = Color(0xFF929296);
  static const border = Color(0xFF38383A);

  /// Accent chosen in settings. UiSettings writes the same value here, and
  /// the theme reads it too. The default matches the «arancio» choice.
  static Color primary = primaryDefault;
  static const Color primaryDefault = Color(0xFFFF5A1F);
  static const primaryDark = Color(0xFFD94C00);
  static const primaryLight = Color(0xFFFF9A62);
  static const secondary = Color(0xFFFFB627);
  static const accent = Color(0xFF2EC4B6);
  static const success = Color(0xFF30D158);
  static const warning = Color(0xFFFFD60A);
  static const error = Color(0xFFFF453A);

  static const qrSurface = Color(0xFFFFFFFF);
  static const qrInk = Color(0xFF000000);

  static const textPrimary = Color(0xFFFFFFFF);
  /// Light pill behind official brand logos.
  static const badgeLight = Color(0xFFF4F4F6);
  static const textSecondary = Color(0xFFAEAEB2);
  static const textMuted = Color(0xFF8E8E93);

  static LinearGradient get brandGradient => LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  /// One TV focus ring, the same stroke TvFocusable paints.
  static const focusRingWidth = 2.5;

  static BorderSide focusRing(
    Set<WidgetState> states,
    Color accent, {
    BorderSide idle = BorderSide.none,
  }) {
    if (states.contains(WidgetState.focused)) {
      return BorderSide(color: accent, width: focusRingWidth);
    }
    return idle;
  }

  static bool get _isApple =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// SF Pro (system) on Apple devices; the bundled heading font elsewhere.
  static String? get _headingFamily => _isApple ? null : 'Sora';

  static ThemeData darkTheme({
    Color accent = AppColors.primaryDefault,
    bool isTv = false,
  }) {
    final onAccent = accent.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      visualDensity: isTv
          ? const VisualDensity(horizontal: -1, vertical: -1)
          : VisualDensity.standard,
      // Apple-inspired: SF on iPhone/iPad (system font), Manrope elsewhere.
      fontFamily: _isApple ? null : 'Manrope',
      // TV: pages change instantly. The animated zoom painted the old and the
      // new page together, which on TV boxes was slow, left both visible for
      // a moment (e.g. the Home behind the player) and wasted memory.
      pageTransitionsTheme: isTv
          ? const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: _InstantPageTransitionsBuilder(),
                TargetPlatform.iOS: _InstantPageTransitionsBuilder(),
                TargetPlatform.fuchsia: _InstantPageTransitionsBuilder(),
                TargetPlatform.linux: _InstantPageTransitionsBuilder(),
                TargetPlatform.macOS: _InstantPageTransitionsBuilder(),
                TargetPlatform.windows: _InstantPageTransitionsBuilder(),
              },
            )
          : const PageTransitionsTheme(
              builders: {
                // iOS-style horizontal slide with edge swipe everywhere.
                TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
              },
            ),
      colorScheme: ColorScheme.dark(
        primary: accent,
        secondary: AppColors.secondary,
        tertiary: AppColors.accent,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: onAccent,
        onSecondary: Colors.black,
        onSurface: AppColors.textPrimary,
      ),
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          letterSpacing: 0,
          color: AppColors.textPrimary,
          fontFamily: _headingFamily,
          fontSize: isTv ? 26 : 22,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        // iOS tab bar: translucent, no pill, tinted icon when selected.
        backgroundColor: AppColors.glass,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? accent : AppColors.textSecondary,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style:
            ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: onAccent,
              elevation: 0,
              minimumSize: isTv ? null : const Size(48, 48),
              padding: EdgeInsets.symmetric(
                horizontal: isTv ? 18 : 24,
                vertical: isTv ? 10 : 14,
              ),

              // Capsule buttons, as on iOS and tvOS.
              shape: const StadiumBorder(),
            ).copyWith(
              side: isTv
                  ? WidgetStateProperty.resolveWith(
                      (states) => focusRing(
                        states,
                        accent,
                        idle: const BorderSide(
                          color: AppColors.clear,
                          width: focusRingWidth,
                        ),
                      ),
                    )
                  : null,
            ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: onAccent,
              minimumSize: const Size(48, 48),
              shape: const StadiumBorder(),
            ).copyWith(
              side: WidgetStateProperty.resolveWith((states) {
                if (!isTv) {
                  return const BorderSide(color: AppColors.clear, width: 3);
                }
                return focusRing(
                  states,
                  accent,
                  idle: const BorderSide(
                    color: AppColors.clear,
                    width: focusRingWidth,
                  ),
                );
              }),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              backgroundColor: AppColors.surface,
              minimumSize: Size(48, isTv ? 44 : 48),
              shape: const StadiumBorder(),
            ).copyWith(
              side: WidgetStateProperty.resolveWith((states) {
                const idle = BorderSide(color: AppColors.border);
                if (!isTv) return idle;
                return focusRing(states, accent, idle: idle);
              }),
            ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(CircleBorder()),
          minimumSize: WidgetStatePropertyAll(
            Size(isTv ? 44 : 48, isTv ? 44 : 48),
          ),
          tapTargetSize: isTv ? null : MaterialTapTargetSize.padded,
          foregroundColor: const WidgetStatePropertyAll(AppColors.textPrimary),
          side: WidgetStateProperty.resolveWith(
            (states) => isTv
                ? focusRing(states, accent)
                : BorderSide.none,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style:
            TextButton.styleFrom(
              foregroundColor: accent,
              shape: const StadiumBorder(),
              minimumSize: Size(isTv ? 44 : 48, isTv ? 44 : 48),
              tapTargetSize: isTv ? null : MaterialTapTargetSize.padded,
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => isTv
                    ? focusRing(states, accent)
                    : BorderSide.none,
              ),
            ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: accent.withValues(alpha: 0.2),
        surfaceTintColor: AppColors.clear,
        side: const BorderSide(color: AppColors.border),
        shape: const StadiumBorder(),
        labelStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: accent,
        dividerColor: AppColors.border,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: AppColors.card,
        contentTextStyle: TextStyle(color: AppColors.textPrimary),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: AppColors.textPrimary,
          fontFamily: _headingFamily,
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          height: 1.2,
        ),
        headlineSmall: TextStyle(
          color: AppColors.textPrimary,
          fontFamily: _headingFamily,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
        headlineMedium: TextStyle(
          color: AppColors.textPrimary,
          fontFamily: _headingFamily,
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          height: 1.2,
        ),
        titleLarge: TextStyle(
          color: AppColors.textPrimary,
          fontFamily: _headingFamily,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
        titleMedium: TextStyle(
          color: AppColors.textPrimary,
          fontFamily: _headingFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
        bodyLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          height: 1.5,
        ),
        labelLarge: TextStyle(
          color: accent,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
      focusColor: accent.withValues(alpha: isTv ? 0.55 : 0.28),
      hoverColor: accent.withValues(alpha: 0.12),
      splashColor: accent.withValues(alpha: 0.18),
      listTileTheme: ListTileThemeData(
        minTileHeight: isTv ? 48 : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        selectedTileColor: accent.withValues(alpha: 0.16),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 0.5,
        space: 0.5,
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? accent : AppColors.track,
        ),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
    );
  }
}

/// TV only: no page animation at all.
class _InstantPageTransitionsBuilder extends PageTransitionsBuilder {
  const _InstantPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
