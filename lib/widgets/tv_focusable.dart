import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/device_type_service.dart';
import '../theme/app_theme.dart';
import '../providers/ui_settings.dart';

import 'package:provider/provider.dart';

/// Production focus roles: debug labels are stripped from release builds.
class EpisodePlaybackFocusNode extends FocusNode {
  EpisodePlaybackFocusNode(String id) : super(debugLabel: 'episode-play:$id');
}

class TvHomeSelectorNode extends FocusNode {
  TvHomeSelectorNode(String label) : super(debugLabel: label);
  bool selected = false;
}

/// Adds remote activation and a consistent TV-only focus ring to custom taps.
///
/// Uses exactly one focus node per item (children are excluded from focus), so
/// the D-Pad never lands on invisible duplicate nodes and moves one item per
/// press. Holding OK triggers [onLongPress].
/// Marks cards inside a HorizontalRow: the row owns their reveal, so the
/// card must not start a second, animated ensureVisible that fights it.
class HorizontalRowScope extends InheritedWidget {
  const HorizontalRowScope({super.key, required super.child});
  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HorizontalRowScope>() != null;
  @override
  bool updateShouldNotify(HorizontalRowScope oldWidget) => false;
}

class TvFocusable extends StatefulWidget {
  final Widget child;
  final FocusNode? focusNode;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final bool autofocus;
  final double focusedScale;
  final BorderRadius borderRadius;
  final ValueChanged<bool>? onFocusChange;
  final bool revealOnFocus;

  const TvFocusable({
    super.key,
    required this.child,
    this.focusNode,
    required this.onPressed,
    this.onLongPress,
    this.autofocus = false,
    this.focusedScale = 1.06,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.onFocusChange,
    this.revealOnFocus = true,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;
  bool _longFired = false;

  /// OK went down on THIS item. A key up alone is ignored: when OK opens a
  /// panel or a page on key down (player buttons, lists), the key up lands
  /// on the first item of the new panel and used to select it at once,
  /// closing the panel unless OK was held.
  bool _pressed = false;

  static bool _isOk(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.gameButtonA;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_isOk(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      _longFired = false;
      _pressed = true;
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) {
      if (!_pressed) return KeyEventResult.handled;
      if (!_longFired && widget.onLongPress != null) {
        _longFired = true;
        widget.onLongPress!();
      }
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      final pressed = _pressed;
      _pressed = false;
      if (pressed && !_longFired) widget.onPressed();
      _longFired = false;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (!DeviceTypeService.isTv) return widget.child;
    final ui = context.select<UiSettings?, bool>(
      (settings) => settings?.animations ?? true,
    );
    final glow = context.select<UiSettings?, bool>(
      (settings) => settings?.focusGlow ?? true,
    );
    final motion = ui && !MediaQuery.disableAnimationsOf(context);
    final duration = motion ? const Duration(milliseconds: 150) : Duration.zero;
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      onFocusChange: (value) {
        if (!value) _pressed = false;
        if (value == _focused) return;
        setState(() => _focused = value);
        widget.onFocusChange?.call(value);
        if (value && widget.revealOnFocus && !HorizontalRowScope.of(context)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_focused) return;
            Scrollable.ensureVisible(
              context,
              duration: duration,
              // Keep context above and below the focused control visible. On
              // TV this avoids clipping row headings when navigating upward.
              alignment: 0.55,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
            );
          });
        }
      },
      child: ExcludeFocus(
        child: RepaintBoundary(
          // A static lift and accent ring preserve focus visibility without
          // rasterising blurred shadows on every frame of remote movement.
          child: Transform.scale(
            scale: _focused && motion ? widget.focusedScale : 1,
            child: Container(
              foregroundDecoration: BoxDecoration(
                borderRadius: widget.borderRadius,
                border: Border.all(
                  color: _focused
                      ? (glow ? AppColors.primary : AppColors.textPrimary)
                      : AppColors.clear,
                  width: 2.5,
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
