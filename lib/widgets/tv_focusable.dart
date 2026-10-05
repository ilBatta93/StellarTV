import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/device_type_service.dart';
import '../theme/app_theme.dart';

/// Adds remote activation and a consistent TV-only focus ring to custom taps.
///
/// Uses exactly one focus node per item (children are excluded from focus), so
/// the D-Pad never lands on invisible duplicate nodes and moves one item per
/// press. Holding OK triggers [onLongPress].
class TvFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final bool autofocus;
  final double focusedScale;
  final BorderRadius borderRadius;
  final ValueChanged<bool>? onFocusChange;

  const TvFocusable({
    super.key,
    required this.child,
    required this.onPressed,
    this.onLongPress,
    this.autofocus = false,
    this.focusedScale = 1.06,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.onFocusChange,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;
  bool _longFired = false;

  static bool _isOk(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.gameButtonA;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_isOk(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      _longFired = false;
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) {
      if (!_longFired && widget.onLongPress != null) {
        _longFired = true;
        widget.onLongPress!();
      }
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      if (!_longFired) widget.onPressed();
      _longFired = false;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (!DeviceTypeService.isTv) return widget.child;
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      onFocusChange: (value) {
        if (value == _focused) return;
        setState(() => _focused = value);
        widget.onFocusChange?.call(value);
      },
      child: ExcludeFocus(
        child: RepaintBoundary(
          child: AnimatedScale(
            scale: _focused ? widget.focusedScale : 1,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: Container(
              foregroundDecoration: BoxDecoration(
                borderRadius: widget.borderRadius,
                border: Border.all(
                  color: _focused ? AppColors.textPrimary : Colors.transparent,
                  width: 3,
                ),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
