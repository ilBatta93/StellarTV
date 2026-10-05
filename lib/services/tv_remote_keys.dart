import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'device_type_service.dart';

/// TV only: lets the D-Pad leave any text field (search bars, dialogs, forms).
///
/// A focused text field normally eats the arrow keys to move the cursor, so
/// with a remote the focus got stuck in it. Up/Down always leave the field,
/// Left/Right leave it only when the cursor is already at the start/end, and
/// OK opens the on-screen keyboard. Touch devices are not affected.
class TvRemoteKeys {
  TvRemoteKeys._();

  static bool _installed = false;

  static void install() {
    if (_installed || !DeviceTypeService.isTv) return;
    _installed = true;
    FocusManager.instance.addEarlyKeyEventHandler(_onKey);
  }

  static KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    final editable = primary?.context
        ?.findAncestorStateOfType<EditableTextState>();
    if (primary == null || editable == null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final value = editable.textEditingValue;
    final sel = value.selection;

    bool move(TraversalDirection dir) {
      final moved = primary.focusInDirection(dir);
      if (moved) SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      return moved;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (!move(TraversalDirection.down)) primary.nextFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      // Not handled when nothing is above: the screen (e.g. the TV top menu)
      // gets the key and takes the focus back.
      return move(TraversalDirection.up)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (!sel.isValid || (sel.isCollapsed && sel.baseOffset <= 0)) {
        return move(TraversalDirection.left)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      }
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (!sel.isValid ||
          (sel.isCollapsed && sel.baseOffset >= value.text.length)) {
        return move(TraversalDirection.right)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      }
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
