import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'device_type_service.dart';
import 'image_warmup_service.dart';

/// TV only: lets the D-Pad leave any text field (search bars, dialogs, forms).
///
/// A focused text field normally eats the arrow keys to move the cursor, so
/// with a remote the focus got stuck in it. Up/Down always leave the field,
/// Left/Right leave it only when the cursor is already at the start/end, and
/// OK opens the on-screen keyboard. Touch devices are not affected.
class TvRemoteKeys {
  TvRemoteKeys._();

  static bool _installed = false;
  static bool? _lastEditing;
  static bool _pendingEditing = false;
  static Timer? _editingDebounceTimer;

  static const _device = MethodChannel('stellartv/device');

  static void install() {
    if (_installed || !DeviceTypeService.isTv) return;
    _installed = true;
    FocusManager.instance.addEarlyKeyEventHandler(_onKey);
    FocusManager.instance.addListener(_syncEditing);
  }

  static bool get _primaryIsEditable =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<EditableTextState>() !=
      null;

  static void _syncEditing() => reportEditing(_primaryIsEditable);

  /// Tells Android whether a text field is being edited, so the system
  /// connects the on-screen keyboard to the app (needed on many Google TV
  /// devices, otherwise the D-Pad closes the keyboard instead of moving in it).
  static void reportEditing(bool editing) {
    if (!DeviceTypeService.isTv) return;
    _pendingEditing = editing;
    _editingDebounceTimer?.cancel();
    _editingDebounceTimer = Timer(const Duration(milliseconds: 50), () {
      if (!DeviceTypeService.isTv) return;
      final current = _lastEditing;
      if (_pendingEditing == current) return;
      _lastEditing = _pendingEditing;
      _device.invokeMethod<void>('setTextEditing', _pendingEditing).catchError((_) {});
    });
  }

  /// Re-checks after a focus change settles (field A -> field B).
  static void recheckEditing() {
    scheduleMicrotask(_syncEditing);
  }

  static KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final arrow = event.logicalKey;
    if (arrow == LogicalKeyboardKey.arrowUp ||
        arrow == LogicalKeyboardKey.arrowDown ||
        arrow == LogicalKeyboardKey.arrowLeft ||
        arrow == LogicalKeyboardKey.arrowRight) {
      RemoteNavigation.note();
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
