import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';

/// Full-screen wait screen shown while playlists are being refreshed.
///
/// It swallows every remote/keyboard key, touch and system Back while a
/// refresh runs, so queued input can never pile up on a busy UI thread and
/// make Android TV / Fire OS kill the app (ANR). Disappears automatically.
class PlaylistRefreshGuard extends StatefulWidget {
  final Widget child;
  const PlaylistRefreshGuard({super.key, required this.child});

  @override
  State<PlaylistRefreshGuard> createState() => _PlaylistRefreshGuardState();
}

class _PlaylistRefreshGuardState extends State<PlaylistRefreshGuard>
    with WidgetsBindingObserver {
  final FocusNode _blocker = FocusNode(debugLabel: 'playlist-refresh-guard');
  FocusNode? _previousFocus;
  Timer? _showDelay;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _showDelay?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _blocker.dispose();
    super.dispose();
  }

  // System Back is ignored while the wait screen is visible.
  @override
  Future<bool> didPopRoute() async => _visible;

  void _sync(bool refreshing) {
    if (refreshing && !_visible) {
      // Short delay: very quick refreshes never flash the screen.
      _showDelay ??= Timer(const Duration(milliseconds: 250), () {
        _showDelay = null;
        if (!mounted) return;
        _previousFocus = FocusManager.instance.primaryFocus;
        setState(() => _visible = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _visible) _blocker.requestFocus();
        });
      });
    } else if (!refreshing) {
      _showDelay?.cancel();
      _showDelay = null;
      if (_visible) {
        setState(() => _visible = false);
        final previous = _previousFocus;
        _previousFocus = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (previous != null && previous.context != null) {
            previous.requestFocus();
          } else {
            _blocker.unfocus();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final refreshing = context.select<AppProvider, bool>(
      (p) => p.isRefreshingAny,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync(refreshing);
    });
    return Stack(
      children: [
        widget.child,
        if (_visible)
          Positioned.fill(
            child: Focus(
              focusNode: _blocker,
              onKeyEvent: (_, _) => KeyEventResult.handled,
              child: const AbsorbPointer(child: _WaitScreen()),
            ),
          ),
      ],
    );
  }
}

class _WaitScreen extends StatelessWidget {
  const _WaitScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ColoredBox(
      color: scheme.surface.withValues(alpha: 0.94),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Aggiornamento in corso',
                textAlign: TextAlign.center,
                style: text.headlineSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Canali, film e serie TV si stanno aggiornando.\n'
                'Attendi qualche istante: l\'app tornerà disponibile da sola.',
                textAlign: TextAlign.center,
                style: text.bodyLarge?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
