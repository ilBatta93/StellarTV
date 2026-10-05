import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/device_type_service.dart';
import '../theme/app_theme.dart';

/// Adds remote activation and a consistent TV-only focus ring to custom taps.
class TvFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final bool autofocus;
  final double focusedScale;
  final BorderRadius borderRadius;

  const TvFocusable({
    super.key,
    required this.child,
    required this.onPressed,
    this.onLongPress,
    this.autofocus = false,
    this.focusedScale = 1.045,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA) {
      widget.onPressed();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (!DeviceTypeService.isTv) return widget.child;
    return Focus(
      onKeyEvent: _onKey,
      child: FocusableActionDetector(
        autofocus: widget.autofocus,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        mouseCursor: SystemMouseCursors.click,
        child: AnimatedScale(
          scale: _focused ? widget.focusedScale : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              border: Border.all(
                color: _focused ? AppColors.primary : Colors.transparent,
                width: 3,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.38),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
