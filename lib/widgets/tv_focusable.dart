import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/device_type_service.dart';
import '../theme/app_theme.dart';
import '../models/poster_focus.dart';
import '../providers/ui_settings.dart';

import 'package:provider/provider.dart';

/// Production focus roles: debug labels are stripped from release builds.
class EpisodePlaybackFocusNode extends FocusNode {
  EpisodePlaybackFocusNode(String id) : super(debugLabel: 'episode-play:$id');
}

// Focus roles are recognised by node type: debug labels are empty in
// release and profile builds, so comparing them never matches on a TV.

/// First stop when the focus enters a page from the top menu (e.g.
/// "Riprendi" in Diretta).
class TvEntryFocusNode extends FocusNode {
  TvEntryFocusNode(String label) : super(debugLabel: label);
}

/// Search button of a catalog toolbar.
class TvSearchFocusNode extends FocusNode {
  TvSearchFocusNode() : super(debugLabel: 'catalogSearch');
}

/// Filter or platform panel opened under a catalog toolbar: arrows stay
/// inside it.
class TvPanelScopeNode extends FocusScopeNode {
  TvPanelScopeNode() : super(debugLabel: 'catalog panel');
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

/// Largest zoom a focused cover may take below this point: "Muro" covers
/// sit 2 px apart, so a zoom would slide under the neighbours.
class PosterFocusCap extends InheritedWidget {
  const PosterFocusCap({super.key, required this.scale, required super.child});
  final double scale;
  static double of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PosterFocusCap>()?.scale ??
      double.infinity;
  @override
  bool updateShouldNotify(PosterFocusCap oldWidget) => scale != oldWidget.scale;
}

class TvFocusable extends StatefulWidget {
  final Widget child;
  final FocusNode? focusNode;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final bool autofocus;
  final double focusedScale;
  final BorderRadius borderRadius;

  /// Ring outline; by default it follows the wrapped button (capsule,
  /// circle) and falls back to [borderRadius].
  final OutlinedBorder? shape;

  /// The child is filled with the accent colour (a selected chip): the
  /// ring turns light so it stays visible.
  final bool onAccent;
  final ValueChanged<bool>? onFocusChange;
  final bool revealOnFocus;

  /// A poster or cover: zoom and ring follow "Effetto di selezione"
  /// instead of [focusedScale] and the standard ring.
  final bool poster;

  const TvFocusable({
    super.key,
    required this.child,
    this.focusNode,
    required this.onPressed,
    this.onLongPress,
    this.autofocus = false,
    this.focusedScale = 1.06,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.shape,
    this.onAccent = false,
    this.onFocusChange,
    this.revealOnFocus = true,
    this.poster = false,
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

  /// Same outline as the wrapped control, so the ring matches its shape.
  OutlinedBorder _ringShape() {
    if (widget.shape case final shape?) return shape;
    final child = _control;
    if (child is IconButton) return const CircleBorder();
    if (child is ButtonStyleButton) {
      final own = child.style?.shape?.resolve(const {});
      return own ?? const StadiumBorder();
    }
    if (child is ChoiceChip) return const StadiumBorder();
    return RoundedRectangleBorder(borderRadius: widget.borderRadius);
  }

  /// Accent-filled buttons get a light ring: an accent ring hugging an
  /// accent capsule would vanish.
  bool get _filled {
    final child = _control;
    return widget.onAccent ||
        (child is ChoiceChip && child.selected) ||
        child is ElevatedButton ||
        child is FilledButton;
  }

  /// The wrapped control, looking through plain layout wrappers.
  Widget get _control {
    var child = widget.child;
    for (var i = 0; i < 3; i++) {
      final inner = switch (child) {
        SizedBox(:final child?) => child,
        Padding(:final child?) => child,
        Align(:final child?) => child,
        ConstrainedBox(:final child?) => child,
        _ => null,
      };
      if (inner == null) break;
      child = inner;
    }
    return child;
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
    final effect = context.select<UiSettings?, (double, double)?>(
      (settings) => widget.poster && settings != null
          ? (
              settings.focusZoom.scale,
              posterFocusRingWidth(settings.focusZoom, settings.focusRing),
            )
          : null,
    );
    final focusedScale = effect == null
        ? widget.focusedScale
        : math.min(effect.$1, PosterFocusCap.of(context));
    // A capped zoom must not leave a cover with no focus mark at all.
    final ringWidth = effect == null
        ? 2.5
        : focusedScale <= 1 && effect.$2 <= 0
        ? PosterFocusRing.thin.width
        : effect.$2;
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
            scale: _focused && motion ? focusedScale : 1,
            child: Container(
              foregroundDecoration: ShapeDecoration(
                shape: _ringShape().copyWith(
                  // Width 0 would still draw a hairline: no ring is none.
                  side: ringWidth <= 0
                      ? BorderSide.none
                      : BorderSide(
                          color: _focused
                              ? (glow && !_filled
                                    ? AppColors.primary
                                    : AppColors.textPrimary)
                              : AppColors.clear,
                          width: ringWidth,
                        ),
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
